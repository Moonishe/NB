#!/usr/bin/env python3
"""Rewrite commit messages using git rebase with exec commands."""
import subprocess, os, sys

os.chdir(r'c:\\Users\\My\\CascadeProjects\\neurobench')

signoff = "\n\nSigned-off-by: Moonishe <rekoslxrdoffical@mail.ru>"

# Map: original subject line -> new full message
msg_map = {
    "Fix 01-core.sql: add DROP FUNCTION for claim_invite_code + close unclosed function": (
        "fix: close unclosed function and add DROP FUNCTION for claim_invite_code\n\n"
        "- Close unclosed function body in 01-core.sql\n"
        "- Add DROP FUNCTION IF EXISTS for claim_invite_code before redefinition"
        + signoff
    ),
    "Rewrite 02-leaderboard.sql for fresh DB: add prompts table, remove old migration steps": (
        "refactor: rewrite 02-leaderboard.sql for fresh DB\n\n"
        "- Add prompts table definition\n"
        "- Remove old migration steps that assumed existing data\n"
        "- Ensure clean installation from scratch"
        + signoff
    ),
    "Fix 06a: add DROP FUNCTION before admin_assign_moderator signature change": (
        "fix: add DROP FUNCTION before admin_assign_moderator signature change\n\n"
        "- Fix 06a-security-fixes.sql: add DROP FUNCTION IF EXISTS\n"
        "- Prevents 'cannot change return type' error on admin_assign_moderator"
        + signoff
    ),
    "Add DROP POLICY IF EXISTS before all CREATE POLICY + fix claim_invite_code DROPs": (
        "fix: add DROP POLICY IF EXISTS and fix claim_invite_code DROPs\n\n"
        "- Add DROP POLICY IF EXISTS before all CREATE POLICY statements\n"
        "- Fix DROP FUNCTION signatures for claim_invite_code variants"
        + signoff
    ),
    "Add IF NOT EXISTS to all indexes in 03-forum.sql": (
        "fix: add IF NOT EXISTS to all indexes in 03-forum.sql\n\n"
        "- Prevents 'relation already exists' errors on re-run\n"
        "- Applied to all CREATE INDEX statements in forum schema"
        + signoff
    ),
    "Add page_views table to 01-core.sql (referenced by js/api.js)": (
        "feat: add page_views table to 01-core.sql\n\n"
        "- Add page_views table definition referenced by js/api.js\n"
        "- Required for view tracking functionality"
        + signoff
    ),
    "Add DROP FUNCTION IF EXISTS before ALL function definitions across all bundles": (
        "fix: add DROP FUNCTION IF EXISTS before all function definitions\n\n"
        "- Applied across all SQL bundle files\n"
        "- Prevents 'cannot change return type of existing function' errors\n"
        "- Ensures idempotent migration execution"
        + signoff
    ),
    "Fix trigger function drops in SQL bundles": (
        "fix: add CASCADE to trigger function drops in SQL bundles\n\n"
        "- Fix DROP FUNCTION statements to include CASCADE\n"
        "- Resolves dependency errors when dropping functions with triggers"
        + signoff
    ),
    "Move admin endorsement achievement seed to achievements bundle": (
        "refactor: move admin endorsement achievement to achievements bundle\n\n"
        "- Move admin endorsement achievement seed data\n"
        "- From core SQL to 04-achievements.sql for better organization"
        + signoff
    ),
    "Fix invalid policy drops on public schema": (
        "fix: use DROP POLICY IF EXISTS for public schema policies\n\n"
        "- Fix invalid policy drops on public schema\n"
        "- Add IF EXISTS to prevent errors on re-run"
        + signoff
    ),
    "fix: restore UTF-8 encoding for all Russian text": (
        "fix: restore UTF-8 encoding for all Russian text\n\n"
        "- Decode multi-layer cp1251/UTF-8 mojibake across HTML, JS, CSS, SQL\n"
        "- Fix Cyrillic text in forum.html, register.html, admin/index.html\n"
        "- Fix Russian strings in profile.js, style.css, SQL files\n"
        "- Fix emoji encoding in achievements (night_shift moon, etc.)"
        + signoff
    ),
    "fix: bump forum.js cache-busting version": (
        "fix: bump forum.js cache-busting version\n\n"
        "- Update query string version in forum.html script tag\n"
        "- Force browsers to load updated JS after encoding fix"
        + signoff
    ),
    "chore: add .gitattributes for UTF-8 enforcement and encoding fix SQL": (
        "chore: add .gitattributes and fix SQL encoding\n\n"
        "- Add .gitattributes to enforce UTF-8 encoding for all text files\n"
        "- Fix remaining mojibake in SQL migration files\n"
        "- Add DROP FUNCTION CASCADE for mod_pin_thread and others"
        + signoff
    ),
    "add forum-remote.js": (
        "feat: add forum-remote.js\n\n"
        "- Add remote forum module for external access\n"
        "- Contains forum functionality for standalone deployment"
        + signoff
    ),
    "fix: remove index.html from URLs for clean routing": (
        "fix: remove index.html from URLs for clean routing\n\n"
        "- Strip index.html from navigation URLs\n"
        "- Ensures clean paths on GitHub Pages deployment"
        + signoff
    ),
}

# Write each message to a temp file and use git commit --amend via rebase --exec
# Strategy: use git rebase -i with all picks, then for each commit, 
# check if the subject matches and amend

# Create the editor script that will be used for each commit during rebase
# We'll use GIT_SEQUENCE_EDITOR to mark all as "pick" (default), 
# then use rebase --exec to amend messages

# Actually, simpler: use git filter-branch with a bash one-liner
# that reads the commit message and replaces it

# Let's try with git rebase + amend approach
# Step 1: Get list of commits
result = subprocess.run(['git', 'log', '-15', '--reverse', '--format=%H %s'], 
                       capture_output=True, text=True)
commits = []
for line in result.stdout.strip().split('\n'):
    if not line.strip():
        continue
    sha, subject = line.split(' ', 1)
    commits.append((sha, subject))

print(f"Found {len(commits)} commits to rewrite")

# Step 2: Do interactive rebase, but we'll use a different approach
# We'll iterate through commits and use git rebase --exec
# Actually, the cleanest way is to use git filter-branch with a proper msg-filter

# Let's write a .sh script for the msg-filter that git can execute
# Using python -c with the messages encoded

import json, base64

# Encode messages as base64 json to avoid escaping issues
encoded = base64.b64encode(json.dumps(msg_map).encode()).decode()

filter_cmd = f'python -c "import sys,json,base64,os; m=json.loads(base64.b64decode(\'{encoded}\').decode()); h=os.environ.get(\'GIT_COMMIT\',\'\')[:7]; s=open(sys.argv[1]).read().split(chr(10))[0]; r=m.get(s,m.get(h,open(sys.argv[1]).read())); open(sys.argv[1],\'w\').write(r)"'

# Get first commit
first_sha = commits[0][0]

env = os.environ.copy()
env['FILTER_BRANCH_SQUELCH_WARNING'] = '1'

# Remove any previous backup
backup = os.path.join('.git', 'refs', 'original', 'refs', 'heads', 'main')
if os.path.exists(backup):
    os.remove(backup)
    # Also remove the directory if empty
    try:
        os.removedirs(os.path.dirname(backup))
    except:
        pass

print(f"Running filter-branch from {first_sha[:7]}^..HEAD")
print(f"Filter command length: {len(filter_cmd)}")

result = subprocess.run(
    ['git', 'filter-branch', '--msg-filter', filter_cmd, '--', f'{first_sha}^..HEAD'],
    capture_output=True, text=True, env=env, cwd=r'c:\Users\My\CascadeProjects\neurobench'
)

print("STDOUT:", result.stdout[-800:] if result.stdout else '(empty)')
if result.stderr:
    print("STDERR:", result.stderr[-800:])
print("Return code:", result.returncode)
