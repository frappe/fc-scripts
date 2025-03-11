import datetime
import re
import os
import contextlib
import sys
import argparse
import json
import csv

# Regex for parsing database logs
# *** (1) TRANSACTION:
transaction_pattern = re.compile(r"\*\*\* \(\d+\) TRANSACTION:")
# TRANSACTION 988653582, ACTIVE 6 sec starting index read
transaction_id_pattern = re.compile(r"TRANSACTION (\d+),")
query_pattern = re.compile(
    r"MariaDB thread id .*\n([\s\S]*)\*\*\* WAITING FOR THIS LOCK TO BE GRANTED"
)
actual_transaction_pattern = re.compile(
    r"\*\*\* WAITING FOR THIS LOCK TO BE GRANTED:\nRECORD LOCKS (.*)\n"
)
conflicted_transaction_pattern = re.compile(
    r"\*\*\* CONFLICTING WITH:\nRECORD LOCKS (.*)\n"
)
trx_id_pattern = re.compile(r"trx id (\d+)")
db_table_pattern = re.compile(r"table `([^`]+)`.`([^`]+)`")


class DatabaseTransactionLog:
    @staticmethod
    def parse(data: str, database: str = None):
        transaction_info = actual_transaction_pattern.search(data).group(1)
        found_database = db_table_pattern.search(transaction_info).group(1)
        if database is not None and database != found_database:
            return None

        return DatabaseTransactionLog(data)

    def __init__(self, data: str):
        self.transaction_id = transaction_id_pattern.search(data).group(1)
        actual_transaction_info = actual_transaction_pattern.search(data).group(1)
        db_table_info = db_table_pattern.search(actual_transaction_info)
        self.database = db_table_info.group(1)
        self.table = db_table_info.group(2)
        self.query = query_pattern.search(data).group(1)

        conflicted_transaction_info = conflicted_transaction_pattern.search(data).group(
            1
        )
        self.conflicted_transaction_id = trx_id_pattern.search(
            conflicted_transaction_info
        ).group(1)
        conflicted_db_table = db_table_pattern.search(conflicted_transaction_info)
        self.conflicted_table = conflicted_db_table.group(2)


def parse_deadlock_trx_log(
    log: str, database: str = None
) -> list[DatabaseTransactionLog]:
    log_lines = log.split("\n")
    log_lines = [line.strip() for line in log_lines]
    log_lines = [line for line in log_lines if line != ""]
    transactions_content = []

    started_transaction_index = None
    for index, line in enumerate(log_lines):
        if transaction_pattern.match(line):
            if started_transaction_index is not None:
                transactions_content.append(
                    "\n".join(log_lines[started_transaction_index:index])
                )
            started_transaction_index = index

    if started_transaction_index is not None:
        transactions_content.append("\n".join(log_lines[started_transaction_index:]))

    transactions = []
    for transaction_content in transactions_content:
        with contextlib.suppress(Exception):
            trx = DatabaseTransactionLog.parse(transaction_content, database)
            if trx is not None:
                transactions.append(trx)

    return transactions


def deadlock_summary(transactions: list[DatabaseTransactionLog]) -> list[dict]:
    transaction_map: dict[str, DatabaseTransactionLog] = {}
    for transaction in transactions:
        transaction_map[transaction.transaction_id] = transaction

    deadlock_transaction_ids = {}

    for transaction in transactions:
        # usually if there is a deadlock, there will be two records
        # one record for deadlock of query A due to query B
        # and another record for deadlock of query B due to query A
        # so, we want to record only one instance of deadlock
        if (
            transaction.conflicted_transaction_id
            and (
                transaction.conflicted_transaction_id not in deadlock_transaction_ids
                or deadlock_transaction_ids[transaction.conflicted_transaction_id]
                != transaction.transaction_id
            )
            and transaction.transaction_id != transaction.conflicted_transaction_id
        ):
            deadlock_transaction_ids[transaction.transaction_id] = (
                transaction.conflicted_transaction_id
            )

    deadlock_infos = []
    for transaction_id in deadlock_transaction_ids:
        if transaction_id not in transaction_map:
            continue
        if transaction.conflicted_transaction_id not in transaction_map:
            continue
        transaction = transaction_map[transaction_id]
        conflicted_transaction = transaction_map[transaction.conflicted_transaction_id]
        deadlock_infos.append(
            {
                "txn_id": transaction.transaction_id,
                "table": transaction.table,
                "conflicted_txn_id": transaction.conflicted_transaction_id,
                "conflicted_table": transaction.conflicted_table,
                "query": transaction.query,
                "conflicted_query": conflicted_transaction.query,
            }
        )
    return deadlock_infos


def parse_innodb_log(
    log_file_path,
    start_datetime: datetime = None,
    end_datetime: datetime = None,
    max_lines: int = -1,
) -> dict[str, str]:
    parsed_logs = []
    current_entry = None

    # Regular expression for the start of a log entry
    log_pattern = re.compile(
        r"(\d{4}-\d{2}-\d{2}\s+\d{1,2}:\d{2}:\d{2})\s+(\d+)\s+\[(\w+)\]\s+(.*)"
    )

    lines = 0
    with open(log_file_path, "r") as file:
        for line in file:
            match = log_pattern.match(line.strip())

            if match:
                # If we have a current entry in progress, save it
                if current_entry:
                    parsed_logs.append(current_entry)

                # Start a new entry
                timestamp, thread_id, log_level, message = match.groups()
                if thread_id == "0":
                    current_entry = None
                    continue

                if log_level != "Note":
                    continue

                timestamp = datetime.datetime.strptime(timestamp, "%Y-%m-%d %H:%M:%S")
                if (start_datetime and timestamp < start_datetime) or (
                    end_datetime and timestamp > end_datetime
                ):
                    continue

                current_entry = {
                    "timestamp": timestamp,
                    "thread_id": int(thread_id),
                    "log_level": log_level,
                    "message": message,
                }
            elif current_entry:
                # This is a continuation line for the current entry
                current_entry["message"] += "\n" + line.strip()

            lines += 1
            if max_lines > 0 and lines > max_lines:
                break

    # add the last entry
    if current_entry:
        parsed_logs.append(current_entry)

    # prepare logs
    log_map: dict[str, list] = {}
    log_timestamp = {}

    for record in parsed_logs:
        thread_id = record["thread_id"]
        if thread_id not in log_map:
            log_map[thread_id] = []
            log_timestamp[thread_id] = record["timestamp"]
        log_map[thread_id].append(record["message"][8:])

    logs = []  # list of tuples (timestamp, log)
    for thread_id in log_map:
        logs.append((log_timestamp[thread_id], "\n".join(log_map[thread_id])))
    return logs


def find_deadlocks(
    log_file: str,
    database: str = None,
    max_lines: int = -1,
    start_datetime: datetime = None,
    end_datetime: datetime = None,
):
    # check file
    if not os.path.exists(log_file):
        print(f"File {log_file} not found")
        exit(1)

    # parse logs
    data = []
    records = parse_innodb_log(
        log_file,
        start_datetime=start_datetime,
        end_datetime=end_datetime,
        max_lines=max_lines,
    )

    for record in records:
        # if "trx" not in record[1]:
        #     continue
        timestamp = record[0]
        transactions = parse_deadlock_trx_log(record[1], database)
        summaries = deadlock_summary(transactions)
        for summary in summaries:
            data.append(
                {
                    "timestamp": str(timestamp),
                    "table": summary["table"],
                    "transaction_id": summary["txn_id"],
                    "query": summary["query"],
                }
            )
            data.append(
                {
                    "timestamp": str(timestamp),
                    "table": summary["conflicted_table"],
                    "transaction_id": summary["conflicted_txn_id"],
                    "query": summary["conflicted_query"],
                }
            )
            data.append({})  # empty line to separate records

    # Strip the queries of any trailing whitespace
    for record in data:
        if "query" not in record:
            continue
        record["query"] = record["query"].rstrip()

    return data


def main():
    """Parse command line arguments and call find_deadlocks function."""
    parser = argparse.ArgumentParser(description="Find deadlocks in MySQL error logs")

    # Required arguments
    parser.add_argument("logfile", help="Path to MySQL error log file")

    # Optional arguments
    parser.add_argument("--database", help="Database Name (optional)")
    parser.add_argument(
        "--days", type=int, help="Only consider entries from the last N days"
    )
    parser.add_argument(
        "--start", help="Only consider entries after this date (YYYY-MM-DD)"
    )
    parser.add_argument(
        "--end", help="Only consider entries before this date (YYYY-MM-DD)"
    )
    parser.add_argument(
        "--max-lines", type=int, help="Maximum number of lines to read from log file"
    )
    parser.add_argument("--output-file", help="Path of file to store result")
    parser.add_argument("--format", help="csv / json / table (default: table)")

    args = parser.parse_args()

    # Process datetime arguments
    start_datetime = None
    end_datetime = None
    database = None
    max_lines = -1
    output_format = None
    output_file = None

    if not args.days and not args.start:
        print("Please provide days or start datetime")
        parser.print_help()
        sys.exit(1)

    if args.days:
        start_datetime = datetime.datetime.now() - datetime.timedelta(days=args.days)

    if args.start:
        try:
            start_datetime = datetime.datetime.strptime(args.start, "%Y-%m-%d")
        except ValueError:
            print("Error: Invalid start date format. Use YYYY-MM-DD", file=sys.stderr)
            parser.print_help()
            sys.exit(1)

    if args.end:
        try:
            end_datetime = datetime.datetime.strptime(args.end, "%Y-%m-%d")
            # Set time to end of day
            end_datetime = end_datetime.replace(hour=23, minute=59, second=59)
        except ValueError:
            print("Error: Invalid end date format. Use YYYY-MM-DD", file=sys.stderr)
            parser.print_help()
            sys.exit(1)

    if args.database:
        database = args.database

    if args.max_lines:
        max_lines = args.max_lines

    if args.format not in ["json", "csv", "table"]:
        output_format = "table"
    else:
        output_format = args.format

    if args.output_file:
        output_file = args.output_file

    deadlocks = find_deadlocks(
        args.logfile,
        database=database,
        start_datetime=start_datetime,
        end_datetime=end_datetime,
        max_lines=max_lines,
    )

    if output_file and os.path.exists(output_file):
        print(f"The file {output_file} already exists. Can't overwrite")
        sys.exit(1)

    fields = ["timestamp", "table", "transaction_id", "query"]
    if output_file:
        output = open(output_file, "w", newline="", encoding="utf-8")
    else:
        output = sys.stdout
    if output_format == "json":
        output.write(json.dumps(deadlocks))
    elif output_format == "csv":
        writer = csv.DictWriter(output, fieldnames=fields)
        writer.writeheader()

        for deadlock in deadlocks:
            # Convert any non-string values to strings
            row = {k: str(v) if v is not None else "" for k, v in deadlock.items()}
            writer.writerow(row)
    elif output_format == "table":
        # Define the field names and their display widths
        widths = {"timestamp": 20, "table": 20, "transaction_id": 15, "query": 40}

        # Print the header row
        header = " | ".join(f"{field:{widths[field]}}" for field in fields)
        separator = "-" * len(header)

        output.write(f"{header}\n")
        output.write(f"{separator}\n")

        # Print each row
        for deadlock in deadlocks:
            row_values = []
            for field in fields:
                # Get value, handle None, and truncate if too long
                value = deadlock.get(field, "")
                if value is None:
                    value = ""
                value_str = str(value).replace("\n", " ")
                row_values.append(f"{value_str:{widths[field]}}")

            output.write(f"{' | '.join(row_values)}\n")

    else:
        print("unsupported format")

    output.close()


if __name__ == "__main__":
    main()
