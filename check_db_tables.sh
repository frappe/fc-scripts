#!/bin/bash

# Check if database name was provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <database_name>"
    exit 1
fi

DB_NAME=$1
TOTAL_TABLES=0
CORRUPTED_TABLES=()

echo "Starting table check for database: \`$DB_NAME\`"

# Get all tables in the database
TABLES=$(mariadb -B -N -e "SHOW TABLES FROM \`$DB_NAME\`;" | sed 's/\r//g')

if [ -z "$TABLES" ]; then
    echo "No tables found in database $DB_NAME or database does not exist."
    exit 1
fi

# Check each table
while IFS= read -r TABLE; do
    echo "Analyzing table: \`$DB_NAME\`.\`$TABLE\`"
    
    CHECK_RESULT=$(mariadb -B -e "CHECK TABLE \`$DB_NAME\`.\`$TABLE\`;" | tail -n 1)
    
    # Extract Msg_type and Msg_text
    MSG_TYPE=$(echo "$CHECK_RESULT" | awk -F'\t' '{print $3}')
    MSG_TEXT=$(echo "$CHECK_RESULT" | awk -F'\t' '{print $4}')
    
    # Add to corrupted tables if Msg_type is not 'status' or if Msg_text is not 'OK'
    if ([ "$MSG_TYPE" != "status" ] || [ "$MSG_TEXT" != "OK" ]) && !([ "$MSG_TYPE" == "note" ] && [ "$MSG_TEXT" == "The storage engine for the table doesn't support check" ]); then
        CORRUPTED_TABLES+=("$TABLE")
        echo "⚠️  Issue detected with table: \`$TABLE\` - $MSG_TYPE: $MSG_TEXT"
    fi
    
    TOTAL_TABLES=$((TOTAL_TABLES + 1))
done <<< "$TABLES"

# Report results
echo ""
echo "==== Table Check Summary ===="
echo "Database: \`$DB_NAME\`"
echo "Total tables checked: $TOTAL_TABLES"

if [ ${#CORRUPTED_TABLES[@]} -eq 0 ]; then
    echo "All tables appear to be in good condition."
else
    echo "Potentially corrupted tables: ${#CORRUPTED_TABLES[@]}"
    echo "----------------------------"
    for TABLE in "${CORRUPTED_TABLES[@]}"; do
        echo "- \`$TABLE\`"
    done
    echo ""
    echo "You may want to run REPAIR TABLE on the affected tables."

    # Ask user if they want to repair tables automatically
    read -p "Do you want to repair the corrupted tables automatically? (y/n): " REPAIR_CONFIRM

    if [[ "$REPAIR_CONFIRM" == "y" || "$REPAIR_CONFIRM" == "Y" ]]; then
        for TABLE in "${CORRUPTED_TABLES[@]}"; do
            TABLE_TYPE=$(mysql -e "SHOW TABLE STATUS LIKE '$TABLE'" | awk 'NR==2 {print $2}')
            
            if [[ "$TABLE_TYPE" == "MyISAM" ]]; then
                # If MyISAM, run REPAIR TABLE
                echo "Repairing MyISAM table: $TABLE"
                mysql -e "REPAIR TABLE \`$TABLE\`"
            elif [[ "$TABLE_TYPE" == "InnoDB" ]]; then
                # If InnoDB, run OPTIMIZE TABLE
                echo "Optimizing InnoDB table: $TABLE"
                mysql -e "OPTIMIZE TABLE \`$TABLE\`"
            else
                echo "Table $TABLE is neither MyISAM nor InnoDB, skipping."
            fi
        done
    else
        echo "No repairs will be made. Please review the tables manually."
    fi
fi