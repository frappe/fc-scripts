# fc-scripts

Helper scripts to be run on Frappe Cloud sites

### Available Scripts

- Script to delete all files from the database and file system. [attachment_delete.py](./attachment_delete.py)
- Read the deadlocks from mariadb error log [analyze_deadlocks.py](./analyze_deadlocks.py)
- Check corruption in MariaDB tables and fix them [check_db_tables.sh](./check_db_tables.sh)

---

## Usage -

### Deadlock Analyzer

Usage -

```
python ./analyze_deadlocks.py  ./mysql-error.log --days 1
```

```
usage: analyze_deadlocks.py [-h] [--database DATABASE] [--days DAYS] [--start START] [--end END] [--max-lines MAX_LINES] [--output-file OUTPUT_FILE] [--format FORMAT] logfile

Find deadlocks in MySQL error logs

positional arguments:
  logfile               Path to MySQL error log file

options:
  -h, --help            show this help message and exit
  --database DATABASE   Database Name (optional)
  --days DAYS           Only consider entries from the last N days
  --start START         Only consider entries after this date (YYYY-MM-DD)
  --end END             Only consider entries before this date (YYYY-MM-DD)
  --max-lines MAX_LINES
                        Maximum number of lines to read from log file
  --output-file OUTPUT_FILE
                        Path of file to store result
  --format FORMAT       csv / json / table (default: table)
```

### MariaDB Table Checker

Need to run as root user

```
./check_db_tables.sh <database_name>
```