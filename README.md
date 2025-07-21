# eSports Calendar Generator

Automatically generates ICS calendar files for eSports matches (LPL, World Championship, MSI) and updates daily via GitHub Actions.

## Features
- Generates calendar files by game type (LPL, World Championship, MSI)
- Generates calendar files by team
- Daily automatic updates via GitHub Actions
- UTC+8 (China time) friendly scheduling

## Directory Structure
```
./
├── games/              # Game-type specific calendar files
│   ├── 2023全球总决赛/
│   │   └── 2023全球总决赛.ics
│   └── ...
├── teams/              # Team-specific calendar files
│   ├── T1/
│   │   └── T1.ics
│   └── ...
├── generate_ics.py     # Main script
└── .github/workflows/  # GitHub Actions configuration
```

## Setup
1. Clone this repository
2. Ensure Python 3.x is installed
3. No additional dependencies required (uses standard libraries)

## Usage
### Manual Execution
```bash
python generate_ics.py
```

### Automatic Updates
The repository includes a GitHub Actions workflow that runs daily at 16:00 (UTC+8). To enable:
1. Push the repository to GitHub
2. Go to repository Settings → Actions → General
3. Enable GitHub Actions

## Calendar Subscription
1. Host the generated ICS files on a web server
2. Use the URL to subscribe in your calendar application

## License
MIT