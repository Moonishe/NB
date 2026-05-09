#!/usr/bin/env python3
"""Generate a git rebase script to rewrite commit messages with detailed descriptions and Signed-off-by."""
import subprocess, os

os.chdir(r'c:\Users\My\CascadeProjects\neurobench')

# Get last 15 commits (oldest first for rebase)
result = subprocess.run(['git', 'log', '--oneline', '-15', '--reverse', '--format=%H %s'], 
                       capture_output=True, text=True)
commits = []
for line in result.stdout.strip().split('\n'):
    parts = line.split(' ', 1)
    commits.append((parts[0], parts[1]))

# Detailed messages for each commit
messages = {
    'f1cb611': (
        "fix: close unclosed function and add DROP FUNCTION for claim_invite_code\n\n"
        "- Close unclosed function body in 01-core.sql\n"
        "- Add DROP FUNCTION IF EXISTS for claim_invite_code before redefinition"
    ),
    '6c8b003': (
        "refactor: rewrite 02-leaderboard.sql for fresh DB\n\n"
        "- Add prompts table definition\n"
        "- Remove old migration steps that assumed existing data\n"
        "- Ensure clean installation from scratch"
    ),
    'fce9e7c': (
        "fix: add DROP FUNCTION before admin_assign_moderator signature change\n\n"
        "- Fix 06a-security-fixes.sql: add DROP FUNCTION IF EXISTS\n"
        "- Prevents 'cannot change return type' error on admin_assign_moderator"
    ),
    '22481ed': (
        "fix: add DROP POLICY IF EXISTS and fix claim_invite_code DROPs\n\n"
        "- Add DROP POLICY IF EXISTS before all CREATE POLICY statements\n"
        "- Fix DROP FUNCTION signatures for claim_invite_code variants"
    ),
    '83c164a': (
        "fix: add IF NOT EXISTS to all indexes in 03-forum.sql\n\n"
        "- Prevents 'relation already exists' errors on re-run\n"
        "- Applied to all CREATE INDEX statements in forum schema"
    ),
    'a77fd76': (
        "feat: add page_views table to 01-core.sql\n\n"
        "- Add page_views table definition referenced by js/api.js\n"
        "- Required for view tracking functionality"
    ),
    '64261e1': (
        "fix: add DROP FUNCTION IF EXISTS before all function definitions\n\n"
        "- Applied across all SQL bundle files\n"
        "- Prevents 'cannot change return type of existing function' errors\n"
        "- Ensures idempotent migration execution"
    ),
    '803dc55': (
        "fix: add CASCADE to trigger function drops in SQL bundles\n\n"
        "- Fix DROP FUNCTION statements to include CASCADE\n"
        "- Resolves dependency errors when dropping functions with triggers"
    ),
    'f43176e': (
        "refactor: move admin endorsement achievement to achievements bundle\n\n"
        "- Move admin endorsement achievement seed data\n"
        "- From core SQL to 04-achievements.sql for better organization"
    ),
    '3a01a34': (
        "fix: use DROP POLICY IF EXISTS for public schema policies\n\n"
        "- Fix invalid policy drops on public schema\n"
        "- Add IF EXISTS to prevent errors on re-run"
    ),
    '36aacbc': (
        "fix: restore UTF-8 encoding for all Russian text\n\n"
        "- Decode multi-layer cp1251/UTF-8 mojibake across HTML, JS, CSS, SQL\n"
        "- Fix Cyrillic text in forum.html, register.html, admin/index.html\n"
        "- Fix Russian strings in profile.js, style.css, SQL files\n"
        "- Fix emoji encoding in achievements (night_shift 🌙, etc.)"
    ),
    '15c6797': (
        "fix: bump forum.js cache-busting version\n\n"
        "- Update query string version in forum.html script tag\n"
        "- Force browsers to load updated JS after encoding fix"
    ),
    'cfcaf67': (
        "chore: add .gitattributes and fix SQL encoding\n\n"
        "- Add .gitattributes to enforce UTF-8 encoding for all text files\n"
        "- Fix remaining mojibake in SQL migration files\n"
        "- Add DROP FUNCTION CASCADE for mod_pin_thread and others"
    ),
    'ddb4cff': (
        "feat: add forum-remote.js\n\n"
        "- Add remote forum module for external access\n"
        "- Contains forum functionality for standalone deployment"
    ),
    '068ce8a': (
        "fix: remove index.html from URLs for clean routing\n\n"
        "- Strip index.html from navigation URLs\n"
        "- Ensures clean paths on GitHub Pages deployment"
    ),
}

signoff = "\n\nSigned-off-by: Moonishe <rekoslxrdoffical@mail.ru>"

# Build rebase todo
print("Will rewrite", len(commits), "commits")
for sha, subject in commits:
    short = sha[:7]
    if short in messages:
        print(f"  {short}: {messages[short].split(chr(10))[0]}")
    else:
        print(f"  {short}: (keep original) {subject}")
