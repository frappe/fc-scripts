# fc-scripts

Helper scripts to be run on Frappe Cloud sites

### Available Scripts

- Script to delete all files from the database and file system. [attachment_delete.py](./attachment_delete.py)
- Read the deadlocks from mariadb error log [analyze_deadlocks.py](./analyze_deadlocks.py)
- Check corruption in MariaDB tables and fix them [check_db_tables.sh](./check_db_tables.sh)
- On premises failover manager setup script [press-on-prem-failover.sh](./press-on-prem-failover.sh)

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


### MariaDB IO Monitor Installation

Run this as root user

```bash
curl -fsSL https://raw.githubusercontent.com/frappe/fc-scripts/refs/heads/develop/mariadb_io_monitor/install.sh | bash -
```

### MariaDB Monitor Installation

Run this as root user

```bash
curl -fsSL https://raw.githubusercontent.com/frappe/fc-scripts/refs/heads/develop/mariadb_monitor/install.sh | bash -
```


### FC On Prem Failover Setup
Run this as root user

For first time setup
```bash
curl -fsSL https://raw.githubusercontent.com/frappe/fc-scripts/refs/heads/develop/press-on-prem-failover.sh -o press-on-prem-failover.sh && chmod +x ./press-on-prem-failover.sh && ./press-on-prem-failover.sh

```

For triggering another setup (for password updates etc.)
```bash
curl -fsSL https://raw.githubusercontent.com/frappe/fc-scripts/refs/heads/develop/press-on-prem-failover.sh -o press-on-prem-failover.sh && chmod +x ./press-on-prem-failover.sh && ./press-on-prem-failover.sh setup

```

### Data Recovery
Setup Necessary Tools

```bash
# Install tools
apt install unzip

# Install mariadb
apt-key add <(curl -fsSL https://mariadb.org/mariadb_release_signing_key.pgp)
DISTRO=$(lsb_release -cs)
echo "deb https://mirror.rackspace.com/mariadb/repo/10.6/ubuntu ${DISTRO} main" | \
  tee /etc/apt/sources.list.d/mariadb.list

apt update
apt install -y mariadb-server mariadb-client libmariadbclient18
systemctl disable mariadb
systemctl stop mariadb || true

ARCH=$(uname -m)

if [[ "$ARCH" == "x86_64" ]]; then
    URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
elif [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
    URL="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

curl "${URL}" -o "awscliv2.zip" && \
unzip awscliv2.zip && \
./aws/install
```


#### Recover
```bash
curl https://raw.githubusercontent.com/frappe/fc-scripts/refs/heads/develop/data_recovery/recover.py -o recover.py
```