# Deploy Agent: Student Attendance Tracker

`deploy_agent.sh` is a shell script that sets up the Student Attendance Tracker, runs it, and archives its logs. It also handles Ctrl+C and Ctrl+Z while a deployment is in progress. The Python file `attendance_checker.py` is never changed.

## Repository layout

```
deploy_agent_GithubUsername/
├── deploy_agent.sh
├── README.md
└── templates/
    ├── attendance_checker.py
    ├── assets.csv
    └── config.json
```

The three files in `templates/` are the original files and are copied as they are.

## How to run it

Make the script executable once, then start it:

```bash
chmod +x deploy_agent.sh
./deploy_agent.sh
```

You will see a menu. Type 1 to deploy, 2 to run the app, 3 to archive the logs, or 4 to exit. You can also skip the menu with a flag: `./deploy_agent.sh --deploy`, `./deploy_agent.sh --run` or `./deploy_agent.sh --archive`. Every feature asks for the project name. If you type `v1`, the project folder is `attendance_tracker_v1/`. Only letters, numbers, `-` and `_` are allowed.

## Feature 1: Deploy

The script first checks that `python3` works (it runs `python3 --version`) and that `zip` is installed. It also checks that the three template files exist. If something is missing, it stops with a clear message.

Then it asks for the project name and creates this structure:

```
attendance_tracker_{name}/
├── attendance_checker.py
├── Helpers/
│   ├── assets.csv
│   └── config.json
└── reports/
```

If the folder already exists, the script asks if you want to overwrite it. If you say no, it stops and changes nothing. `reports/` starts empty. The app creates its own logs there.

`attendance_checker.py` and `config.json` are copied from `templates/`. For the roster, the script asks you to choose:

- **Option A** copies the number of students you choose (plus the header) from `templates/assets.csv`. These students already have 4 sessions each, so `total_sessions` stays at 5.
- **Option B** makes a new roster from name and email lists inside the script. All counts start at 0, so the script sets `total_sessions` to 1 with `sed`.

The rule is that `total_sessions` is always one more than the sessions already recorded in the roster. The app counts today's session as the extra one. This is why Option B needs the change to 1.

If any step fails, for example `cp` or `chmod` with "permission denied", the script prints an error, removes the half-made project folder, and stops.

### Permissions

The script runs `chmod +x` on `attendance_checker.py` and `chmod 600` on `Helpers/config.json`, so only the owner can read and write the thresholds. It then prints the permissions it set.

### Updating the thresholds

The script asks if you want to change the alert thresholds. If you say yes, it asks for a warning value (default 75) and a failure value (default 50). Pressing Enter keeps the default. Each value must be a whole number. Warning must be from 1 to 100, and failure must be lower than warning. If the input is not valid, the script asks again, so `sed` only ever gets a clean number.

`sed` then edits only the `"warning"` and `"failure"` lines inside `config.json`. The file is not reformatted or reordered.

### Verifying the deployment

At the end of deploy, the script starts the app (Feature 2). If the app starts and shows the marking prompts, the structure, roster and config work together. This first run counts as a real session.

## Feature 2: Run

The script goes into `attendance_tracker_{name}/` and runs `python3 attendance_checker.py`. The terminal belongs to the instructor, who marks each student present or absent.

Before every run, the script calls `sync_total_sessions`. It finds the highest number of recorded sessions in `assets.csv` and sets `total_sessions` to that number plus one. Without this, running the app more than once would push a student above 100%. For example, 6 attended sessions out of a total of 5 gives 120%.

## Feature 3: Archive

After a run, the script looks for `reports/attendance.log` and `reports/absent.log`. Each log that exists is moved into its own folder with a timestamp in the name:

```
attendance_tracker_{name}/archives/
├── attendance/attendance_YYYYMMDD_HHMMSS.log
└── absent/absent_YYYYMMDD_HHMMSS.log
```

The timestamp makes every archived file unique. The script prints the final path of each archived log. If a log does not exist, for example nobody was absent, it says so and continues without crashing. The logs are moved, not copied, so the next run starts with clean reports.

## Ctrl+C and Ctrl+Z during deploy

While a deployment is running, the script traps SIGINT (Ctrl+C) and SIGTSTP (Ctrl+Z). When either one arrives, the script:

1. prints a message that the deployment was interrupted,
2. zips whatever exists of the project into `attendance_tracker_{name}_archive.zip` with the `zip` command,
3. deletes the incomplete project folder, and
4. exits cleanly.

The trap is turned off when the setup finishes, so it does not affect the marking session inside the Python app.

### How to test it

1. Run `./deploy_agent.sh` and choose 1.
2. Enter a project name, for example `test`.
3. At the "Choose A or B" prompt, press Ctrl+C (then repeat with Ctrl+Z in a new deploy).
4. Check the result:

```bash
ls
unzip -l attendance_tracker_test_archive.zip
```

You should see the zip file and no `attendance_tracker_test/` folder. The zip contains what had been created by that point: the project folder, `Helpers/`, `reports/`, `attendance_checker.py` and `config.json`. Because you interrupted before the roster was made, `assets.csv` is not inside.

## How the deployment was tested

After a deploy, I checked the structure with `ls -R attendance_tracker_{name}` and checked the permissions with `ls -l`. I opened `Helpers/config.json` to confirm the thresholds changed and `total_sessions` matched the roster. Then I ran the app twice and checked that nobody goes above 100%. I tested bad input too: letters instead of numbers, an empty project name, and a failure threshold higher than the warning threshold. I also tested an existing project name, answering both yes and no to the overwrite question.
That is the video link https://drive.google.com/file/d/1CBffya1c5s7B8MbbNe6kbLZEsIeTnMRg/view?usp=sharing
