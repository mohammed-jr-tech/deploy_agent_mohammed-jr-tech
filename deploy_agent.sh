#!/bin/bash

secript_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
templates_directory="$secript_directory/templates"
cd "$secript_directory" || exit 1

CREATED_DIR="" 

handle_interrupt() {
    trap - INT TSTP
    echo
    echo "Deployment interrupted (Ctrl+C or Ctrl+Z pressed)."
    if [ -n "$CREATED_DIR" ] && [ -d "$CREATED_DIR" ]; then
        local zipname="${CREATED_DIR}_archive.zip"
        echo "Archiving the incomplete project into $zipname ..."
        if zip -r -q "$zipname" "$CREATED_DIR"; then
            echo "Archive created: $secript_directory/$zipname"
            rm -rf "$CREATED_DIR"
            echo "Incomplete directory $CREATED_DIR removed."
        else
            echo "Could not create the zip. Leaving $CREATED_DIR in place."
        fi
    else
        echo "archive directory not found"
    fi
    echo "Closing the session cleanly. Goodbye."
    exit 130
}


check_project_name() {
    local input
    read -r -p "Enter the project name (e.g. v1): " input
    if [[ ! "$input" =~ ^[A-Za-z0-9_-]+$ ]]; then
        echo "Error: use only letters, numbers, - and _ (and not empty)." >&2
        return 1
    fi
    PROJECT_NAME="$input"
    PROJECT_DIR="attendance_tracker_${input}"
}

is_number() { [[ "$1" =~ ^[0-9]+$ ]]; }


sync_total_sessions() {
    local dir="$1"
    local roster="$dir/Helpers/assets.csv"
    local cfg="$dir/Helpers/config.json"
    local prior
    prior=$(awk -F, 'NR>1 { s=$3+$4; if (s>m) m=s } END { print m+0 }' "$roster")
    sed -i.bak -E "s/(\"total_sessions\":[[:space:]]*)[0-9]+/\1$((prior + 1))/" "$cfg"
    rm -f "${cfg}.bak"
}

run_app_in() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        echo "Error: $dir does not exist. Deploy first." >&2
        return 1
    fi
    sync_total_sessions "$dir"
    echo "Starting the Attendance Tracker in $dir ..."
    ( cd "$dir" && python3 attendance_checker.py )
}

run_feature() {
    check_project_name || return 1
    run_app_in "$PROJECT_DIR"
}

deploy_feature() {
    local missing=0
    for tool in python3 zip; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            echo "Error: '$tool' is not installed. Please install it and try again." >&2
            missing=1
        fi
    done
    [ "$missing" -eq 1 ] && return 1

    for f in attendance_checker.py assets.csv config.json; do
        if [ ! -f "$templates_directory/$f" ]; then
            echo "Error: templates_directory/$f not found." >&2
            return 1
        fi
    done

    
    trap handle_interrupt INT TSTP


    check_project_name || { trap - INT TSTP; return 1; }

    if [ -d "$PROJECT_DIR" ]; then
        read -r -p "$PROJECT_DIR already exists. Overwrite it? (y/N): " ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            rm -rf "$PROJECT_DIR"
        else
            echo "Aborted. Nothing was changed."
            trap - INT TSTP
            return 1
        fi
    fi

    CREATED_DIR="$PROJECT_DIR"
    mkdir -p "$PROJECT_DIR/Helpers" "$PROJECT_DIR/reports" || {
        echo "Error: could not create directories." >&2
        trap - INT TSTP
        return 1
    }
    echo "Created $PROJECT_DIR/, Helpers/ and reports/."

    # 3. Populate files
    cp "$templates_directory/attendance_checker.py" "$PROJECT_DIR/attendance_checker.py"
    cp "$templates_directory/config.json" "$PROJECT_DIR/Helpers/config.json"

    local roster="$PROJECT_DIR/Helpers/assets.csv"
    local template_rows
    template_rows=$(( $(wc -l < "$templates_directory/assets.csv") - 1 ))

    echo
    echo "How do you want to build the roster?"
    echo "  A) Copy from the template (up to $template_rows students, 4 prior sessions each)"
    echo "  B) Generate a fresh roster (all counts start at 0)"
    local choice n
    while true; do
        read -r -p "Choose A or B: " choice || handle_interrupt
        [[ "$choice" =~ ^[AaBb]$ ]] && break
        echo "Please type A or B."
    done

    if [[ "$choice" =~ ^[Aa]$ ]]; then
        while true; do
            read -r -p "How many students to copy (1-$template_rows)? " n || handle_interrupt
            if is_number "$n" && [ "$n" -ge 1 ] && [ "$n" -le "$template_rows" ]; then break; fi
            echo "Enter a number between 1 and $template_rows."
        done
        head -n $((n + 1)) "$templates_directory/assets.csv" > "$roster"
        echo "Copied $n students from the template (total_sessions stays 5)."
    else
        local names=("Amina Yusuf" "Brian Okello" "Chloe Uwase" "David Mugisha" "Eva Ingabire"
                     "Farid Hassan" "Grace Mukamana" "Hamza Ali" "Isabelle Niyonsenga" "Jonas Habimana"
                     "Khadija Omar" "Liam Kagame" "Mariam Nkusi" "Nathan Byiringiro" "Olivia Teta"
                     "Peter Nsengimana" "Queen Uwimana" "Reem Salih" "Samuel Mutesi" "Tasha Kayitesi")
        local emails=("amina" "brian" "chloe" "david" "eva" "farid" "grace" "hamza" "isabelle" "jonas"
                      "khadija" "liam" "mariam" "nathan" "olivia" "peter" "queen" "reem" "samuel" "tasha")
        local max=${#names[@]}
        while true; do
            read -r -p "How many students to generate (1-$max)? " n || handle_interrupt
            if is_number "$n" && [ "$n" -ge 1 ] && [ "$n" -le "$max" ]; then break; fi
            echo "Enter a number between 1 and $max."
        done
        echo "Email,Names,Attendance Count,Absence Count" > "$roster"
        local i
        for ((i = 0; i < n; i++)); do
            echo "${emails[$i]}@example.com,${names[$i]},0,0" >> "$roster"
        done
        
        sed -i.bak -E 's/("total_sessions":[[:space:]]*)[0-9]+/\11/' "$PROJECT_DIR/Helpers/config.json"
        rm -f "$PROJECT_DIR/Helpers/config.json.bak"
        echo "Generated $n students (total_sessions set to 1)."
    fi

    chmod +x "$PROJECT_DIR/attendance_checker.py"
    chmod 600 "$PROJECT_DIR/Helpers/config.json"
    echo
    echo "Permissions set:"
    ls -l "$PROJECT_DIR/attendance_checker.py" "$PROJECT_DIR/Helpers/config.json" | awk '{print "  " $1 "  " $NF}'

    echo
    read -r -p "Update the attendance alert thresholds? (y/N): " upd
    if [[ "$upd" =~ ^[Yy]$ ]]; then
        local w f
        while true; do
            read -r -p "Warning threshold [default 75]: " w || handle_interrupt
            w=${w:-75}
            if is_number "$w" && [ "$w" -le 100 ]; then break; fi
            echo "Enter a whole number from 0 to 100."
        done
        while true; do
            read -r -p "Failure threshold [default 50]: " f || handle_interrupt
            f=${f:-50}
            if is_number "$f" && [ "$f" -le 100 ]; then break; fi
            echo "Enter a whole number from 0 to 100."
        done
        if [ "$f" -ge "$w" ]; then
            echo "Warning: failure ($f) is not lower than warning ($w). Applying anyway."
        fi
        local cfg="$PROJECT_DIR/Helpers/config.json"
        sed -i.bak -E "s/(\"warning\":[[:space:]]*)[0-9]+/\1${w}/; s/(\"failure\":[[:space:]]*)[0-9]+/\1${f}/" "$cfg"
        rm -f "${cfg}.bak"
        echo "Thresholds updated: warning=$w, failure=$f"
    else
        echo "Keeping default thresholds."
    fi

    trap - INT TSTP
    CREATED_DIR=""

    echo
    echo "Deployment complete. Verifying by starting the application..."
    run_app_in "$PROJECT_DIR"
}


archive_feature() {
    check_project_name || return 1
    if [ ! -d "$PROJECT_DIR" ]; then
        echo "Error: $PROJECT_DIR does not exist." >&2
        return 1
    fi

    local ts
    ts=$(date +%Y%m%d_%H%M%S)
    local archived=0

    mkdir -p "$PROJECT_DIR/archives/attendance" "$PROJECT_DIR/archives/absent"

    local att="$PROJECT_DIR/reports/attendance.log"
    local abs="$PROJECT_DIR/reports/absent.log"

    if [ -f "$att" ]; then
        local dest="$PROJECT_DIR/archives/attendance/attendance_${ts}.log"
        mv "$att" "$dest" && echo "Archived: $dest" && archived=$((archived + 1))
    else
        echo "No attendance.log found (nothing to archive)."
    fi

    if [ -f "$abs" ]; then
        local dest="$PROJECT_DIR/archives/absent/absent_${ts}.log"
        mv "$abs" "$dest" && echo "Archived: $dest" && archived=$((archived + 1))
    else
        echo "No absent.log found (nobody absent, or the app has not run yet)."
    fi

    echo "Done. $archived log file(s) archived."
}

show_menu() {
    echo "========================================"
    echo "  Student Attendance Tracker - Deploy Agent"
    echo "========================================"
    echo "  1) Deploy the application"
    echo "  2) Run the application"
    echo "  3) Archive the log files"
    echo "  4) Exit"
}

case "$1" in
    --deploy)  deploy_feature; exit $? ;;
    --run)     run_feature; exit $? ;;
    --archive) archive_feature; exit $? ;;
esac

while true; do
    show_menu
    read -r -p "Choose an option (1-4): " opt
    case "$opt" in
        1) deploy_feature ;;
        2) run_feature ;;
        3) archive_feature ;;
        4) echo "Goodbye."; exit 0 ;;
        *) echo "Invalid option. Please choose 1, 2, 3 or 4." ;;
    esac
    echo
done
