#!/bin/bash

################################################################################
# Script: trino-time-travel.sh
# Description: Query Iceberg table snapshots using Trino time travel
# Usage: ./scripts/trino-time-travel.sh
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source colors
source "${SCRIPT_DIR}/common/colors.sh"

TRINO_NAMESPACE="${TRINO_NAMESPACE:-trino}"
CATALOG="${CATALOG:-iceberg}"
SCHEMA="${SCHEMA:-default}"

########################################
# Helper Functions
########################################

require_cmd() {
  if ! command -v "$1" &>/dev/null; then
    echo -e "${RED}Error: Required command '$1' not found${NC}"
    exit 1
  fi
}

trino_exec() {
  local query="$1"
  kubectl exec -n "${TRINO_NAMESPACE}" deployment/trino -- trino --execute "$query" 2>/dev/null || {
    echo -e "${RED}Error: Failed to execute Trino query${NC}"
    return 1
  }
}

########################################
# Main Script
########################################

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Iceberg Time Travel Query Tool${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

# Check prerequisites
require_cmd kubectl

# Verify Trino is running
if ! kubectl get deployment trino -n "${TRINO_NAMESPACE}" &>/dev/null; then
  echo -e "${RED}Error: Trino deployment not found in namespace '${TRINO_NAMESPACE}'${NC}"
  echo "Please deploy Trino first by running:"
  echo "  export TABLEFLOW_BACKEND='minio'"
  echo "  ./demo-startup.sh"
  exit 1
fi

# Check if Trino pod is ready
if ! kubectl wait --for=condition=ready pod -l app=trino -n "${TRINO_NAMESPACE}" --timeout=5s &>/dev/null; then
  echo -e "${RED}Error: Trino pod is not ready${NC}"
  echo "Please ensure Trino is running."
  exit 1
fi

# List available tables
echo -e "${YELLOW}Step 1: Discovering Tableflow tables...${NC}"
echo

tables_output=$(trino_exec "SHOW TABLES FROM ${CATALOG}.${SCHEMA}" | grep -v "WARNING" | tr -d '"' || true)

if [ -z "$tables_output" ]; then
  echo -e "${RED}No tables found in ${CATALOG}.${SCHEMA}${NC}"
  echo "Please ensure data is flowing through the Tableflow pipeline."
  exit 1
fi

# Parse tables into array (portable way)
tables_array=()
while IFS= read -r line; do
  if [ -n "$line" ]; then
    tables_array+=("$line")
  fi
done <<< "$tables_output"

if [ "${#tables_array[@]}" -eq 0 ]; then
  echo -e "${RED}No tables found${NC}"
  exit 1
fi

# Select table
if [ "${#tables_array[@]}" -eq 1 ]; then
  selected_table="${tables_array[0]}"
  echo -e "${GREEN}Found 1 table: ${selected_table}${NC}"
  echo
else
  echo "Available tables:"
  for i in "${!tables_array[@]}"; do
    echo "  $((i+1))) ${tables_array[$i]}"
  done
  echo
  read -p "Select table number (1-${#tables_array[@]}): " table_choice

  if ! [[ "$table_choice" =~ ^[0-9]+$ ]] || [ "$table_choice" -lt 1 ] || [ "$table_choice" -gt "${#tables_array[@]}" ]; then
    echo -e "${RED}Invalid selection${NC}"
    exit 1
  fi

  selected_table="${tables_array[$((table_choice-1))]}"
  echo
fi

echo -e "${YELLOW}Step 2: Fetching snapshots for table '${selected_table}'...${NC}"
echo

# Query snapshots using Iceberg system table
snapshot_query="SELECT
  snapshot_id,
  CAST(committed_at AS VARCHAR) as committed_at,
  operation
FROM ${CATALOG}.${SCHEMA}.\"${selected_table}\$snapshots\"
ORDER BY committed_at DESC"

snapshots_output=$(trino_exec "$snapshot_query" | grep -v "WARNING" || true)

if [ -z "$snapshots_output" ]; then
  echo -e "${RED}No snapshots found for table '${selected_table}'${NC}"
  exit 1
fi

# Display snapshots table
echo "Snapshots (most recent first):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "$snapshots_output" | head -1  # Header
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "$snapshots_output" | tail -n +2  # Data rows
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# Parse snapshots into arrays (portable way)
snapshot_lines=()
while IFS= read -r line; do
  if [ -n "$line" ]; then
    snapshot_lines+=("$line")
  fi
done <<< "$(echo "$snapshots_output" | tail -n +2)"

if [ "${#snapshot_lines[@]}" -eq 0 ]; then
  echo -e "${RED}No snapshot data available${NC}"
  exit 1
fi

# Extract snapshot IDs and timestamps
declare -a snapshot_ids
declare -a snapshot_times

for line in "${snapshot_lines[@]}"; do
  # Parse comma-delimited output with quotes: "snapshot_id","timestamp","operation"
  # Remove all quotes and split by comma
  clean_line=$(echo "$line" | tr -d '"')

  snapshot_id=$(echo "$clean_line" | awk -F',' '{print $1}' | xargs)
  snapshot_time=$(echo "$clean_line" | awk -F',' '{print $2}' | xargs)

  if [ -n "$snapshot_id" ] && [ -n "$snapshot_time" ]; then
    snapshot_ids+=("$snapshot_id")
    snapshot_times+=("$snapshot_time")
  fi
done

if [ "${#snapshot_ids[@]}" -eq 0 ]; then
  echo -e "${RED}Failed to parse snapshot IDs${NC}"
  exit 1
fi

# Select snapshot
echo -e "${YELLOW}Step 3: Select a snapshot to query${NC}"
echo
echo "Available snapshots:"
for i in "${!snapshot_ids[@]}"; do
  echo "  $((i+1))) Snapshot ID: ${snapshot_ids[$i]} (${snapshot_times[$i]})"
done
echo

read -p "Select snapshot number (1-${#snapshot_ids[@]}): " snapshot_choice

if ! [[ "$snapshot_choice" =~ ^[0-9]+$ ]] || [ "$snapshot_choice" -lt 1 ] || [ "$snapshot_choice" -gt "${#snapshot_ids[@]}" ]; then
  echo -e "${RED}Invalid selection${NC}"
  exit 1
fi

selected_snapshot_id="${snapshot_ids[$((snapshot_choice-1))]}"
selected_snapshot_time="${snapshot_times[$((snapshot_choice-1))]}"

echo
echo -e "${GREEN}✓ Selected snapshot: ${selected_snapshot_id} (${selected_snapshot_time})${NC}"
echo

# Get total row count for this snapshot first
echo -e "${YELLOW}Counting rows in snapshot...${NC}"
count_query="SELECT COUNT(*) as total_rows FROM ${CATALOG}.${SCHEMA}.\"${selected_table}\" FOR VERSION AS OF ${selected_snapshot_id}"
total_rows=$(trino_exec "$count_query" | grep -v "WARNING" | tail -1 | tr -d '"' || echo "0")
echo

# Ask for row limit
echo -e "${YELLOW}Step 4: Configure query${NC}"
echo
echo "Total rows in this snapshot: ${total_rows}"
read -p "Number of rows to display (default: 10, max: ${total_rows}): " row_limit
row_limit="${row_limit:-10}"

if ! [[ "$row_limit" =~ ^[0-9]+$ ]]; then
  echo -e "${RED}Invalid number${NC}"
  exit 1
fi

# Cap at total rows
if [ "$row_limit" -gt "$total_rows" ]; then
  echo -e "${YELLOW}Note: Limited to ${total_rows} rows (total available)${NC}"
  row_limit=$total_rows
fi

# Execute time travel query
echo
echo -e "${YELLOW}Step 5: Executing time travel query...${NC}"
echo
echo -e "${YELLOW}Query:${NC}"
echo "  SELECT ordertime, orderid, itemid, orderunits,"
echo "         address.city, address.state, address.zipcode"
echo "  FROM \"${selected_table}\""
echo "  FOR VERSION AS OF ${selected_snapshot_id}"
echo "  LIMIT ${row_limit}"
echo

# Query with formatted columns for better readability
time_travel_query="SELECT
  ordertime,
  orderid,
  itemid,
  ROUND(orderunits, 2) as orderunits,
  address.city as city,
  address.state as state,
  address.zipcode as zipcode
FROM ${CATALOG}.${SCHEMA}.\"${selected_table}\"
FOR VERSION AS OF ${selected_snapshot_id}
ORDER BY ordertime DESC
LIMIT ${row_limit}"

echo -e "${GREEN}Results (${row_limit} rows):${NC}"
echo

# Execute query with better formatting
result=$(kubectl exec -n "${TRINO_NAMESPACE}" deployment/trino -- trino \
  --output-format ALIGNED \
  --execute "$time_travel_query" 2>/dev/null | grep -v "WARNING" || true)

if [ -z "$result" ]; then
  echo -e "${YELLOW}No data returned (snapshot may be empty)${NC}"
else
  echo "$result"
fi

echo

# Show statistics comparison
echo -e "${YELLOW}Snapshot Statistics:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Get current count
current_count_query="SELECT COUNT(*) as total_rows FROM ${CATALOG}.${SCHEMA}.\"${selected_table}\""
current_count=$(trino_exec "$current_count_query" | grep -v "WARNING" | tail -1 | tr -d '"' || echo "0")

# Calculate percentage using bc if available, otherwise skip decimal
if command -v bc &>/dev/null && [ "$total_rows" -gt 0 ] && [ "$current_count" -gt 0 ]; then
  percentage=$(echo "scale=1; ($total_rows * 100) / $current_count" | bc)
else
  percentage="N/A"
fi

printf "  %-20s : %d rows\n" "Snapshot (selected)" "$total_rows"
printf "  %-20s : %d rows\n" "Current (latest)" "$current_count"
echo "  ────────────────────────────────────────────────────────"

if [ "$total_rows" != "$current_count" ]; then
  diff=$((current_count - total_rows))
  if [ $diff -gt 0 ]; then
    if command -v bc &>/dev/null && [ "$total_rows" -gt 0 ]; then
      change_pct=$(echo "scale=1; ($diff * 100) / $total_rows" | bc)
      printf "  %-20s : ${GREEN}+%d rows (+%s%%)${NC}\n" "Change" "$diff" "$change_pct"
    else
      printf "  %-20s : ${GREEN}+%d rows${NC}\n" "Change" "$diff"
    fi
  else
    abs_diff=$((diff * -1))
    if command -v bc &>/dev/null && [ "$total_rows" -gt 0 ]; then
      change_pct=$(echo "scale=1; ($abs_diff * 100) / $total_rows" | bc)
      printf "  %-20s : ${RED}-%d rows (-%s%%)${NC}\n" "Change" "$abs_diff" "$change_pct"
    else
      printf "  %-20s : ${RED}-%d rows${NC}\n" "Change" "$abs_diff"
    fi
  fi
  if [ "$percentage" != "N/A" ]; then
    printf "  %-20s : %s%% of current data\n" "Snapshot coverage" "$percentage"
  fi
else
  printf "  %-20s : ${GREEN}No change${NC}\n" "Change"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Time Travel Query Complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo
echo -e "${YELLOW}💡 Additional Commands:${NC}"
echo
echo "View all data from this snapshot:"
echo "  kubectl exec -n trino deployment/trino -- trino --output-format ALIGNED --execute \\"
echo "    'SELECT ordertime, orderid, itemid, orderunits, address.city, address.state"
echo "     FROM ${CATALOG}.${SCHEMA}.\"${selected_table}\""
echo "     FOR VERSION AS OF ${selected_snapshot_id}'"
echo
echo "Compare with current snapshot:"
echo "  kubectl exec -n trino deployment/trino -- trino --output-format ALIGNED --execute \\"
echo "    'SELECT \"snapshot\" as source, COUNT(*) as row_count"
echo "     FROM ${CATALOG}.${SCHEMA}.\"${selected_table}\""
echo "     FOR VERSION AS OF ${selected_snapshot_id}"
echo "     UNION ALL"
echo "     SELECT \"current\" as source, COUNT(*) as row_count"
echo "     FROM ${CATALOG}.${SCHEMA}.\"${selected_table}\"'"
echo
echo "View snapshot metadata:"
echo "  kubectl exec -n trino deployment/trino -- trino --output-format ALIGNED --execute \\"
echo "    'SELECT * FROM ${CATALOG}.${SCHEMA}.\"${selected_table}\\\$snapshots\""
echo "     WHERE snapshot_id = ${selected_snapshot_id}'"
echo
