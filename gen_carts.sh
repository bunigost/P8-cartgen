#!/bin/bash  
# --------------------------------
# gen_carts.sh - Generates carts   
# --------------------------------

# usage : ./gen_carts.sh
# run with --parallel flag to process with more than one job 

# Number of parallel jobs
NUM_JOBS=8

# Directory setup
BASE_DIR=$(pwd)
MD_CARTSFILE=$BASE_DIR/carts.md

FILES_DIR=$BASE_DIR/files
MINID_FILE=$FILES_DIR/min_id.txt
NOTCARTSID_FILE=$FILES_DIR/notcarts.txt

TEMP_DIR=$BASE_DIR/.temp
CSV_CARTSFILE=$TEMP_DIR/temp_carts.csv
PIDS_FILE=$TEMP_DIR/pids.txt
PROGRESS_DIR=$TEMP_DIR/progress
LOG_DIR=$TEMP_DIR/logs

for dir in "$FILES_DIR" "$TEMP_DIR" "$LOG_DIR" "$PROGRESS_DIR"; do
  [ ! -d "$dir" ] && mkdir "$dir"
done

[ ! -f "$MD_CARTSFILE" ]  && printf "| %-6s | %-26s | %-15s |\n" "ID" "TITLE" "AUTHOR" > "$MD_CARTSFILE"
[ ! -f "$CSV_CARTSFILE" ] && echo "ID,TITLE,AUTHOR,added_by" > "$CSV_CARTSFILE"

# get MIN_ID from minid.txt if it exists, else use default value
get_minid() {
  if [ -s "$MINID_FILE" ]; then
      min_id=$(cat $MINID_FILE)
  else  
      min_id=1  # Default value  
  fi
}

get_maxid () {
  # get last post ID from BBS superblog
  BREADCRUMBS_LINE=$(curl -s "https://www.lexaloffle.com/bbs/superblog.php?" | grep -m 1 '<div class=breadcrumbs')
    
  max_id=$(echo "$BREADCRUMBS_LINE" | grep -oP 'href="/bbs/\?pid=\K\d+' | head -n 1)
}
  
# log function
log() {
  local i="$1"
  echo "$2" >> "$LOG_DIR/log"$i".txt"
}

# update progress files :
# used to retrieve progress when stopping script, see in start function
# only available when processing in parallel
update_progress () {
  local data="$1"
  local file="$2"
  [ $PARALLEL -eq 1 ] && echo "$data" > "$file"
}

# update carts files : add 5th argument to print in temp_cartsfile
# function used to add a cart in carts files
print_entry() {
  local ID=$1
  local TITLE=$2
  local AUTHOR=$3
  local JOB=$4
  
  if [ -z "$5" ]; then
    printf "| %-6s | %-26s | %-15s |\n" "$ID" "$TITLE" "by $AUTHOR" >> "$MD_CARTSFILE"
  else
    echo "$ID,$TITLE,$AUTHOR,job$JOB" >> "$CSV_CARTSFILE"
  fi
}

# Stop all jobs when Ctrl + C
cleanstop() {
  echo -e "\nStopping all jobs..."
  if [ $PARALLEL -ne "0" ]; then
    while IFS= read -r line; do
    kill $line &> /dev/null
    done < "$PIDS_FILE"
    rm "$PIDS_FILE"
  fi
  wait
  exit
}

trap cleanstop INT

# Function to define what to do when done processing IDs
cartgen_done() {
  
  # get next time min_id by getting the higher ID in temp_carts.csv
  tail -n +2 $CSV_CARTSFILE | sort -t ',' -k1,1nr | head -n 1 | cut -d ',' -f1 > $MINID_FILE

  # delete pids.txt (file used to store background jobs pids)
  [ -f $PIDS_FILE ] && rm "$PIDS_FILE"
  
  # ask before cleaning progress and log dirs
  echo 

  read -s -n 1 -p "Delete progress and log files ? [y/n] " clean
  clean=${clean:-n}
  echo 
  if [[ $clean =~ ^[Yy]$ ]]; then
    rm -r "$PROGRESS_DIR" "$LOG_DIR"
    echo "Progress and log files deleted!"
  fi
}

# Function to process the ID range
carts_gen() {  

  local i="$1"
  local start="$2"    
  local end="$3"

  range=$((start - end))
  echo "Starting Job [$i] from [$start] to [$end] - Range : [$range]"

  time=$(date "+%d-%m - %H:%M")

  log $i "-------------------------"
  log $i "  GENERATING CARTS LOGS"
  log $i "  $time"
  log $i "-------------------------"

  for ((ID=start; ID>=end; ID-- )); do

    log $i "-------------------------"
    log $i "  Processing ID $ID"
    
    # Checking if ID is in notcarts first, a file containing IDs of posts wrongfully flagged as PICO-8 carts in previous gens
    if [ -f "$NOTCARTSID_FILE" ]; then
      if grep -P "\b$ID\b" "$NOTCARTSID_FILE"; then
        echo "Job [$1] : Skipping ID [$ID]  - not a cart"
        log $i "  ID $ID skipped, found in notcarts.txt"
        update_progress "$start|$end|$ID" "$PROGRESS_FILE"
        continue
      fi
    fi
    # Define URL to check
    URL="https://www.lexaloffle.com/bbs/?pid=${ID}"    
    # fetch page content    
    PAGE_CONTENT=$(curl -s "$URL")
  
    # extract the content between <body></body>    
    BODY_CONTENT=$(echo "$PAGE_CONTENT" | awk "/<body>/{flag=1;next}/<\/body>/{flag=0}flag")    
    # look for <div class=breadcrumbs> inside <body></body>    
    BREADCRUMBS_LINE=$(echo "$BODY_CONTENT" | grep '<div class=breadcrumbs')   

    # update progress files
    update_progress "$start|$end|$ID" "$PROGRESS_FILE"
    
    # if no breadcrumbs div, move to next id
    if [ -z "$BREADCRUMBS_LINE" ]; then 
      echo "Job [$i] - Skipping ID [$ID] - No breadcrumbs div"
      log $i "  Skipping ID $ID : No breadcrumbs found"
      continue    
    fi    

    # Check for both "PICO-8" and "Cartridges" in the breadcrumbs line   
    if echo "$BREADCRUMBS_LINE" | grep -q "PICO-8" && echo "$BREADCRUMBS_LINE" | grep -q "Cartridges"; then

      # Extract TITLE from <title></title> in <head>    
      TITLE=$(echo "$PAGE_CONTENT" | grep -oP '(?<=<title>).*?(?=</title>)' | sed 's/ - Lexaloffle BBS//') 
  
      AUTHOR=$(echo "$BODY_CONTENT" | awk '/<div class=breadcrumbs/{exit} {prev=$0} END{print prev}' | grep -oP '(?<=<b style="color:#fff;font-size:12pt">).*?(?=</b>)')
            
      log $i "$ID - BBS Title : |$TITLE| - BBS Author : |$AUTHOR|"

      # clean TITLE and AUTHOR for temp_carts.csv by removing special characters for easier duplicates check
      TEMP_TITLE=$(echo "$TITLE" | tr -d -c '[:alnum:]_')
      TEMP_AUTHOR=$(echo "$AUTHOR" | tr -d -c '[:alnum:]_')

      # keeping the original title and author if its only special characters
      # currently causing issues because making duplicates
      if [ -z "$TEMP_TITLE" ]; then
        TEMP_TITLE="$TITLE"
        tput bel
        echo "ID [$ID] Original Title set as title"
      fi
      
      if [ -z "b$TEMP_AUTHOR" ]; then
        TEMP_AUTHOR="$AUTHOR"
        tput bel
        echo "ID [$ID] Original Author set as author"
      fi
      
      log $i "cleaned TITLE : |$TEMP_TITLE| - cleaned AUTHOR : |$TEMP_AUTHOR|"
      
      # If TEMP_TITLE is in CSV_CARTSFILE
        if grep -Pq "\b$TEMP_TITLE\b" "$CSV_CARTSFILE"; then

          log $i "$TEMP_TITLE found in carts.csv"   
          
          # Get the line in a variable  
          TITLE_LINE=$(cat "$CSV_CARTSFILE" | grep -P "\b$TEMP_TITLE\b")
          
          # Check if TEMP_AUTHOR exists in that variable
          if grep -Pq "\b$TEMP_AUTHOR\b" <<< "$TITLE_LINE"; then
            
            log $i "cleaned author $TEMP_AUTHOR found in cart.csv"
            
            # get the line with the same author and same title in a variable
            FULL_LINE="$(cat "$CSV_CARTSFILE" | grep -P "\b$TEMP_TITLE\b,\b$TEMP_AUTHOR\b")"
            
            # Extract the ID from the line with TEMP_TITLE and TEMP_AUTHOR
            EXISTING_ID=$(echo "$FULL_LINE" | cut -d',' -f1)

            log $i "ID in carts : $EXISTING_ID - BBS ID : $ID - FULL EXISTING LINE : $FULL_LINE"
             
             # check if the ID is bigger than the one in carts file    
            if [[ "$ID" -gt "$EXISTING_ID" ]]; then 
            
              echo "Job [$i] - [$ID | $TITLE | by $AUTHOR] - Updating [$FULL_LINE] entry in carts file"     
              
              log $i "replacing $FULL_LINE with $ID $TITLE $AUTHOR"

              # remove existing_line from cartsfiles
              sed -i "/|[[:space:]]*$EXISTING_ID[[:space:]]*|/d" "$MD_CARTSFILE"
              # remove existing_line from csv_cartsfile
              sed -i "/$FULL_LINE/d" "$CSV_CARTSFILE"
              # add updated lines
              print_entry "$ID" "$TITLE" "$AUTHOR"
              print_entry "$ID" "$TEMP_TITLE" "$TEMP_AUTHOR" "$i" temp
            else # existing id > id
              log $i "ID $ID greater than existing ID $EXISTING_ID, not updating carts file"
              
              echo "Job [$i] - [$ID | $TITLE] - Already in carts"
                  
            fi
          else # Same title, different author
            log $i "adding $ID $TITLE $AUTHOR in carts cause not the same author but same title"
            
            echo "Job [$i] - Adding [$ID | $TITLE | by $AUTHOR] to PICO-8 carts"
          
            print_entry "$ID" "$TEMP_TITLE" "$TEMP_AUTHOR" "$i" temp
            print_entry "$ID" "$TITLE" "$AUTHOR"
          fi             
        else # TITLE not in carts
          echo "Job [$i] - Adding [$ID | $TITLE | by $AUTHOR] to PICO-8 carts"
              
          print_entry "$ID" "$TITLE" "$AUTHOR"
          print_entry "$ID" "$TEMP_TITLE" "$TEMP_AUTHOR" "$i" temp
        fi
    fi

  done

  tput bel
  
  echo "Job [$i] - All IDs processed"

  [ $PARALLEL -eq 0 ] && cartgen_done
  
}

# Function to distribute the workload between jobs
share_workload () {
  
  local end_id="$1"
  local start_id="$2"

  # Loop to define range to process for each job
  for i in $(seq 1 $NUM_JOBS); do
  
    end_id=$((start_id - range_by_job))
    
    # give the remainder to last job
      if [ "$i" -eq "$NUM_JOBS" ]; then
        end_id=$min_id
      fi
    
    # generate progress file
    PROGRESS_FILE="$PROGRESS_DIR/job"$i".txt"
    echo "$start_id|$end_id|$start_id" > "$PROGRESS_FILE"

    # launch jobs and save pids to be able able to kill with CTRL+C
    carts_gen "$i" "$start_id" "$end_id" & 
    echo "$!" >> "$PIDS_FILE"

    # update start_id for the next job
    start_id=$((end_id - 1))
  done

  wait

  cartgen_done
}

# Function to start generating carts
start() {
  
  PARALLEL=0
  
  get_minid
  get_maxid
  
  total_range=$((max_id - min_id))
  
  # if no parallel flag
  if [ -z "$1" ]; then
    PARALLEL=0
    echo -e "Processing IDs from $max_id to $min_id with [1] job.\nRange is $total_range."
    
    ! read -r -t 10 -p "Press [Enter] to proceed " && echo && exit
    
    carts_gen "1" "$max_id" "$min_id"

  # elif parallel flag
  elif [ "$1" = "--parallel" ];then
    PARALLEL=1
    
    # first check if there's a parallel generation in progress by checking for progress file for more than one job
    
    PROGRESS2="$PROGRESS_DIR/job2.txt"

    # check if progress files exist
      if [ -f "$PROGRESS2" ]; then
      
        # first loop to echo remaining work and ask for confirmation before proceeding
        for i in $(seq 1 $NUM_JOBS); do
          PROGRESS_FILE="$PROGRESS_DIR/job"$i".txt"
          # parse
          IFS='|' read -r start end current < "$PROGRESS_FILE"
      
          job_remaining=$((current - end))
          total_remaining=$((total_remaining + job_remaining))
          
          [ $i -eq 1 ] && first_id=$start
          [ $i -eq $NUM_JOBS ] && last_id=$end
        done
    
        remaining_by_job=$((total_remaining / NUM_JOBS ))
        echo -e "Resuming previously started generation from [$first_id] to [$last_id] with [$NUM_JOBS] jobs.\nTotal remaining range is [$total_remaining]. Approx. remaining range per job is [$current]."
        ! read -r -t 10 -p "Press [Enter] to proceed " && echo && exit
        echo
        
        # second loop to read from found progress files and launch jobs
        for i in $(seq 1 $NUM_JOBS); do
          PROGRESS_FILE="$PROGRESS_DIR/job"$i".txt"
          # parse
          IFS='|' read -r start end current < "$PROGRESS_FILE"

          carts_gen "$i" "$current" "$end" &
          # store pids for easy kill
          echo "$!" >> "$PIDS_FILE"
        done

        wait

        cartgen_done
        
      # Progress files not found
      else
        range_by_job=$(( (max_id - min_id) / $NUM_JOBS ))    
      
        echo -e "Processing IDs from [$max_id] to [$min_id] with [$NUM_JOBS] jobs.\nTotal range is [$total_range] and range per job is [$range_by_job]."
    
        ! read -r -t 10 -p "Press [Enter] to proceed " && echo && exit
        echo
        
        share_workload "$min_id" "$max_id"
      fi
  fi
}

start "$@"