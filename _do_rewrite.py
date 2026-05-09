#!/usr/bin/env python3
"""Rewrite git commit messages with detailed descriptions and Signed-off-by using git filter-branch."""
import subprocess, os, sys

os.chdir(r'c:\Users\My\CascadeProjects\neurobench')

signoff = "\n\nSigned-off-by: Moonishe <rekoslxrdoffical@mail.ru>"

messages = {
    'f1cb611': (
        "fix: close unclosed function and add DROP FUNCTION for claim_invite_code\n\n"
        "- Close unclosed function body in 01-core.sql\n"
        "- Add DROP FUNCTION IF EXISTS for claim_invite_code before redefinition"
        + signoff
    ),
    '6c8b003': (
        "refactor: rewrite 02-leaderboard.sql for fresh DB\n\n"
        "- Add prompts table definition\n"
        "- Remove old migration steps that assumed existing data\n"
        "- Ensure clean installation from scratch"
        + signoff
    ),
    'fce9e7c': (
        "fix: add DROP FUNCTION before admin_assign_moderator signature change\n\n"
        "- Fix 06a-security-fixes.sql: add DROP FUNCTION IF EXISTS\n"
        "- Prevents 'cannot change return type' error on admin_assign_moderator"
        + signoff
    ),
    '22481ed': (
        "fix: add DROP POLICY IF EXISTS and fix claim_invite_code DROPs\n\n"
        "- Add DROP POLICY IF EXISTS before all CREATE POLICY statements\n"
        "- Fix DROP FUNCTION signatures for claim_invite_code variants"
        + signoff
    ),
    '83c164a': (
        "fix: add IF NOT EXISTS to all indexes in 03-forum.sql\n\n"
        "- Prevents 'relation already exists' errors on re-run\n"
        "- Applied to all CREATE INDEX statements in forum schema"
        + signoff
    ),
    'a77fd76': (
        "feat: add page_views table to 01-core.sql\n\n"
        "- Add page_views table definition referenced by js/api.js\n"
        "- Required for view tracking functionality"
        + signoff
    ),
    '64261e1': (
        "fix: add DROP FUNCTION IF EXISTS before all function definitions\n\n"
        "- Applied across all SQL bundle files\n"
        "- Prevents 'cannot change return type of existing function' errors\n"
        "- Ensures idempotent migration execution"
        + signoff
    ),
    '803dc55': (
        "fix: add CASCADE to trigger function drops in SQL bundles\n\n"
        "- Fix DROP FUNCTION statements to include CASCADE\n"
        "- Resolves dependency errors when dropping functions with triggers"
        + signoff
    ),
    'f43176e': (
        "refactor: move admin endorsement achievement to achievements bundle\n\n"
        "- Move admin endorsement achievement seed data\n"
        "- From core SQL to 04-achievements.sql for better organization"
        + signoff
    ),
    '3a01a34': (
        "fix: use DROP POLICY IF EXISTS for public schema policies\n\n"
        "- Fix invalid policy drops on public schema\n"
        "- Add IF EXISTS to prevent errors on re-run"
        + signoff
    ),
    '36aacbc': (
        "fix: restore UTF-8 encoding for all Russian text\n\n"
        "- Decode multi-layer cp1251/UTF-8 mojibake across HTML, JS, CSS, SQL\n"
        "- Fix Cyrillic text in forum.html, register.html, admin/index.html\n"
        "- Fix Russian strings in profile.js, style.css, SQL files\n"
        "- Fix emoji encoding in achievements (night_shift moon, etc.)"
        + signoff
    ),
    '15c6797': (
        "fix: bump forum.js cache-busting version\n\n"
        "- Update query string version in forum.html script tag\n"
        "- Force browsers to load updated JS after encoding fix"
        + signoff
    ),
    'cfcaf67': (
        "chore: add .gitattributes and fix SQL encoding\n\n"
        "- Add .gitattributes to enforce UTF-8 encoding for all text files\n"
        "- Fix remaining mojibake in SQL migration files\n"
        "- Add DROP FUNCTION CASCADE for mod_pin_thread and others"
        + signoff
    ),
    'ddb4cff': (
        "feat: add forum-remote.js\n\n"
        "- Add remote forum module for external access\n"
        "- Contains forum functionality for standalone deployment"
        + signoff
    ),
    '068ce8a': (
        "fix: remove index.html from URLs for clean routing\n\n"
        "- Strip index.html from navigation URLs\n"
        "- Ensures clean paths on GitHub Pages deployment"
        + signoff
    ),
}

# Build the filter-branch command with a message map
# Create a file that maps old hashes to new messages
msg_filter = '''
import sys, os
# Read the original commit hash from the environment
orig_hash = os.environ.get('GIT_COMMIT', '')
short = orig_hash[:7]

messages = ''' + repr(messages) + '''

msg = open(sys.argv[1], 'r').read()
if short in messages:
    with open(sys.argv[1], 'w') as f:
        f.write(messages[short])
'''

# Write the msg-filter script
with open('_msg_filter.py', 'w') as f:
    f.write(msg_filter)

print("Running git filter-branch...")
print("This will rewrite the last 15 commits with detailed messages + Signed-off-by")

# Get the root commit of the last 15
result = subprocess.run(
    ['git', 'log', '-15', '--reverse', '--format=%H'],
    capture_output=True, text=True
)
first_commit = result.stdout.strip().split('\n')[0]
print(f"Root commit for rebase: {first_commit[:7]}")

# Run filter-branch
result = subprocess.run(
    ['git', 'filter-branch', '--msg-filter', 'python _msg_filter.py', 
     '--', f'{first_commit}^..HEAD'],
    capture_output=True, text=True
)
print("STDOUT:", result.stdout)
if result.stderr:
    print("STDERR:", result.stderr[-500:])
print("Return code:", result.returncode)

# Cleanup
os.remove('_msg_filter.py')
