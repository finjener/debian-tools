#!/usr/bin/env python3
# git_multi_setup — brief
# Manages multiple SSH keys and per-repo gitconfig files for multiple git hosts.
# Quick usage:
# 1) Generate template: scripts/development/git_multi_setup.py --generate-template
# 2) Edit ~/.config/git-multi/config.yaml (set accounts and ssh_key_path)
# 3) Preview: scripts/development/git_multi_setup.py --setup-ssh --dry-run
# 4) Apply:   scripts/development/git_multi_setup.py --setup-ssh
#
# YAML (~/ .config/git-multi/config.yaml) notes:
# - top-level `accounts`: list of account blocks.
# - account fields: `id`, `provider` (github/gitlab), `user_name`, `user_email`,
#   `ssh_key_path` (exact filename or pattern with `{}`), `host_alias`,
#   `usernames` (list of provider usernames to create per-username keys),
#   `repo_base_dirs` (optional paths used to write includeIf entries),
#   `rewrite_remotes` (optional).
# - If you supply an explicit `ssh_key_path`, the script uses it verbatim
#   and will NOT append usernames automatically (unless you include `{}`).
#
# Git config behavior:
# - The script writes per-repo/per-username gitconfig files named
#   `~/.gitconfig.<id>.<username>` containing `[user]` and a `[repo]` name.
# - If `repo_base_dirs` are provided, the script will add
#   `includeIf "gitdir:<base>/<username>/**"` entries to your `~/.gitconfig`
#   so the per-username gitconfig is applied automatically when inside that
#   repository path. Backups of modified files are saved with `.bak` suffix.
#
import argparse
import os
from pathlib import Path
import socket
import subprocess
import stat
import yaml

DEFAULT_CONFIG_PATH = os.path.expanduser("~/.config/git-multi/config.yaml")
# for more accounts multiply the part from -id: to defaults.
DEFAULT_TEMPLATE = """accounts:
  - id: github-personal
    provider: github
    display_name: "My Personal GitHub"
    user_name: "Your Name"
    user_email: "you@example.com"
    ssh_key_path: "~/.ssh/id_ed25519_github_personal"    # base key path; if you include '{}' it will be replaced by the account username
    host_alias: "github-personal"
    usernames: ["username"]   # list of account usernames (previously called repos)
    repo_base_dirs: ["~/projects/personal"]
    rewrite_remotes: false
defaults:
  config_path: "~/.config/git-multi/config.yaml"
  ssh_config_path: "~/.ssh/config"
  global_gitconfig: "~/.gitconfig"
  generate_ssh_keys: true
  backup: true
"""

def key_base_for_account(acct: dict) -> str:
    ssh = acct.get("ssh_key_path") or ""
    ssh = ssh.strip()
    if "{}" in ssh:
        return os.path.expanduser(ssh)
    # default to <id>_id_ed25519 naming
    aid = acct.get("id") or "unknown"
    return os.path.expanduser(f"~/.ssh/{aid}_id_ed25519")

def write_template(path: str) -> None:
    expanded = os.path.expanduser(path)
    config_file = Path(expanded)
    if config_file.exists():
        print(f"Config already exists at {expanded}")
        return
    config_file.parent.mkdir(parents=True, exist_ok=True)
    config_file.write_text(DEFAULT_TEMPLATE)
    print(f"Wrote template config to {expanded}")

def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", "-c", default=DEFAULT_CONFIG_PATH)
    parser.add_argument("--generate-template", action="store_true")
    parser.add_argument("--generate-keys", action="store_true")
    parser.add_argument("--print-keys", action="store_true")
    parser.add_argument("--apply-ssh-config", action="store_true")
    parser.add_argument("--apply-gitconfigs", action="store_true")
    parser.add_argument("--rewrite-remotes", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--setup-ssh", action="store_true")
    return parser.parse_args()

def main():
    args = parse_args()
    if args.generate_template:
        write_template(args.config)
        return
    if args.generate_keys:
        cfg_path = os.path.expanduser(args.config)
        if not os.path.exists(cfg_path):
            print(f"Config not found at {cfg_path}; run --generate-template first")
            return
        data = yaml.safe_load(Path(cfg_path).read_text(encoding="utf-8"))
        for acct in data.get("accounts", []):
            base = key_base_for_account(acct)
            usernames = acct.get("usernames") or []
            if usernames:
                for username in usernames:
                    if "{}" in (acct.get("ssh_key_path") or ""):
                        keypath = base.format(username)
                    else:
                        keypath = base
                    if os.path.exists(keypath):
                        print(f"Key exists: {keypath}")
                        continue
                    keydir = os.path.dirname(keypath)
                    os.makedirs(keydir, exist_ok=True)
                    hostname = socket.gethostname()
                    comment = f"{acct.get('id')}@{hostname}"
                    cmd = ["ssh-keygen", "-t", "ed25519", "-f", keypath, "-C", comment, "-N", ""]
                    print(f"Generating key for {acct.get('id')}/{username} at {keypath} (comment: {comment})")
                    subprocess.check_call(cmd)
                    os.chmod(keypath, stat.S_IRUSR | stat.S_IWUSR)
                    try:
                        os.chmod(keypath + ".pub", stat.S_IRUSR | stat.S_IWUSR | stat.S_IRGRP | stat.S_IROTH)
                    except FileNotFoundError:
                        pass
            else:
                keypath = base
                if os.path.exists(keypath):
                    print(f"Key exists: {keypath}")
                else:
                    keydir = os.path.dirname(keypath)
                    os.makedirs(keydir, exist_ok=True)
                    hostname = socket.gethostname()
                    comment = f"{acct.get('id')}@{hostname}"
                    cmd = ["ssh-keygen", "-t", "ed25519", "-f", keypath, "-C", comment, "-N", ""]
                    print(f"Generating key for {acct.get('id')} at {keypath} (comment: {comment})")
                    subprocess.check_call(cmd)
                    os.chmod(keypath, stat.S_IRUSR | stat.S_IWUSR)
                    try:
                        os.chmod(keypath + ".pub", stat.S_IRUSR | stat.S_IWUSR | stat.S_IRGRP | stat.S_IROTH)
                    except FileNotFoundError:
                        pass
        return
    if args.setup_ssh:
        cfg_path = os.path.expanduser(args.config)
        if not os.path.exists(cfg_path):
            print(f"Config not found at {cfg_path}; run --generate-template first")
            return
        data = yaml.safe_load(Path(cfg_path).read_text(encoding="utf-8"))

        # generate missing keys (per-repo if repos listed, otherwise per-account)
        for acct in data.get("accounts", []):
            base = acct.get("ssh_key_path") or f"~/.ssh/id_ed25519_{acct.get('id')}"
            base = os.path.expanduser(base)
            repos = acct.get("repos") or []
            if repos:
                for repo in repos:
                    if "{}" in base:
                        keypath = base.format(repo)
                    else:
                        keypath = base
                    if os.path.exists(keypath):
                        print(f"Key exists: {keypath}")
                        continue
                    keydir = os.path.dirname(keypath)
                    os.makedirs(keydir, exist_ok=True)
                    hostname = socket.gethostname()
                    comment = f"{acct.get('id')}@{hostname}"
                    cmd = ["ssh-keygen", "-t", "ed25519", "-f", keypath, "-C", comment, "-N", ""]
                    print(f"Generating key for {acct.get('id')}/{repo} at {keypath} (comment: {comment})")
                    subprocess.check_call(cmd)
                    os.chmod(keypath, stat.S_IRUSR | stat.S_IWUSR)
                    try:
                        os.chmod(keypath + ".pub", stat.S_IRUSR | stat.S_IWUSR | stat.S_IRGRP | stat.S_IROTH)
                    except FileNotFoundError:
                        pass
            else:
                keypath = base
                if os.path.exists(keypath):
                    print(f"Key exists: {keypath}")
                else:
                    keydir = os.path.dirname(keypath)
                    os.makedirs(keydir, exist_ok=True)
                    hostname = socket.gethostname()
                    comment = f"{acct.get('id')}@{hostname}"
                    cmd = ["ssh-keygen", "-t", "ed25519", "-f", keypath, "-C", comment, "-N", ""]
                    print(f"Generating key for {acct.get('id')} at {keypath} (comment: {comment})")
                    subprocess.check_call(cmd)
                    os.chmod(keypath, stat.S_IRUSR | stat.S_IWUSR)
                    try:
                        os.chmod(keypath + ".pub", stat.S_IRUSR | stat.S_IWUSR | stat.S_IRGRP | stat.S_IROTH)
                    except FileNotFoundError:
                        pass

        # ensure SSH host blocks
        ssh_conf_path = os.path.expanduser(data.get("defaults", {}).get("ssh_config_path", "~/.ssh/config"))
        existing = ""
        if os.path.exists(ssh_conf_path):
            existing = Path(ssh_conf_path).read_text(encoding="utf-8")
        new_blocks = []
        # create Host blocks per-repo or per-account
        for acct in data.get("accounts", []):
            provider = acct.get("provider")
            hostname = "github.com" if provider == "github" else "gitlab.com" if provider == "gitlab" else provider
            host_base = acct.get("host_alias") or acct.get("id")
            base = acct.get("ssh_key_path") or f"~/.ssh/id_ed25519_{acct.get('id')}"
            base = os.path.expanduser(base)
            usernames = acct.get("usernames") or []
            if usernames:
                for username in usernames:
                    host = f"{host_base}-{username}"
                    if "{}" in acct.get("ssh_key_path", ""):
                        identity = base.format(username)
                    else:
                        identity = base
                    block = []
                    block.append(f"Host {host}")
                    block.append(f"    HostName {hostname}")
                    block.append("    User git")
                    block.append(f"    IdentityFile {identity}")
                    block.append("    IdentitiesOnly yes")
                    block_text = "\n".join(block) + "\n"
                    if block_text.strip() in existing:
                        print(f"SSH Host block for {host} already present in {ssh_conf_path}")
                        continue
                    new_blocks.append(block_text)
            else:
                host = host_base
                identity = base
                block = []
                block.append(f"Host {host}")
                block.append(f"    HostName {hostname}")
                block.append("    User git")
                block.append(f"    IdentityFile {identity}")
                block.append("    IdentitiesOnly yes")
                block_text = "\n".join(block) + "\n"
                if block_text.strip() in existing:
                    print(f"SSH Host block for {host} already present in {ssh_conf_path}")
                    continue
                new_blocks.append(block_text)
        if new_blocks:
            if args.dry_run:
                print("--- DRY RUN: SSH blocks to add ---")
                for b in new_blocks:
                    print(b)
            else:
                backup_path = ssh_conf_path + ".bak"
                if os.path.exists(ssh_conf_path):
                    Path(backup_path).write_text(existing, encoding="utf-8")
                    print(f"Backed up existing ssh config to {backup_path}")
                with Path(ssh_conf_path).open("a", encoding="utf-8") as f:
                    for b in new_blocks:
                        f.write("\n" + b)
                print(f"Appended {len(new_blocks)} Host blocks to {ssh_conf_path}")

        # print public keys and testing/clone instructions
        print("\nSSH setup complete. For each account add the following public key to the service and then run the test command below:")
        for acct in data.get("accounts", []):
            host_base = acct.get("host_alias") or acct.get("id")
            base = acct.get("ssh_key_path") or f"~/.ssh/id_ed25519_{acct.get('id')}"
            base = os.path.expanduser(base)
            usernames = acct.get("usernames") or []
            if usernames:
                for username in usernames:
                    host = f"{host_base}-{username}"
                    if "{}" in acct.get("ssh_key_path", ""):
                        pub = base.format(username) + ".pub"
                    else:
                        pub = base + ".pub"
                    print("\n---")
                    print(f"Account: {acct.get('id')} ({acct.get('provider')}) username: {username}")
                    if os.path.exists(pub):
                        print(f"Public key ({pub}):")
                        print(Path(pub).read_text(encoding="utf-8").strip())
                    else:
                        print(f"Public key not found: {pub}")
                    if args.dry_run:
                        print("\nDRY RUN: would prompt for key registration and run ssh test for this username")
                        continue
                    ans = input(f"Press Enter after adding the key for {acct.get('id')}/{username} to the provider web UI, or type 'skip' to skip the test: ")
                    if ans.strip().lower() == 'skip':
                        print(f"Skipping test for {acct.get('id')}/{username}")
                        continue
                    print(f"Running SSH test: ssh -T {host}")
                    try:
                        res = subprocess.run(["ssh", "-T", host], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30, check=False)
                        print("--- SSH test output ---")
                        print(res.stdout)
                        print(f"SSH test exited with code {res.returncode}")
                    except subprocess.TimeoutExpired:
                        print("SSH test timed out")
                    except subprocess.SubprocessError as err:
                        print(f"SSH test failed: {err}")
                    print("If successful, clone this repository (replace <owner>):")
                    print(f"git clone git@{host}:<owner>/{username}.git")
            else:
                host = host_base
                pub = base + ".pub"
                print("\n---")
                print(f"Account: {acct.get('id')} ({acct.get('provider')})")
                if os.path.exists(pub):
                    print(f"Public key ({pub}):")
                    print(Path(pub).read_text(encoding="utf-8").strip())
                else:
                    print(f"Public key not found: {pub}")
                if args.dry_run:
                    print("\nDRY RUN: would prompt for key registration and run ssh test")
                    continue
                ans = input(f"Press Enter after adding the key for {acct.get('id')} to the provider web UI, or type 'skip' to skip the test: ")
                if ans.strip().lower() == 'skip':
                    print(f"Skipping test for {acct.get('id')}")
                    continue
                print(f"Running SSH test: ssh -T {host}")
                try:
                    res = subprocess.run(["ssh", "-T", host], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=30, check=False)
                    print("--- SSH test output ---")
                    print(res.stdout)
                    print(f"SSH test exited with code {res.returncode}")
                except subprocess.TimeoutExpired:
                    print("SSH test timed out")
                except subprocess.SubprocessError as err:
                    print(f"SSH test failed: {err}")
                print("If successful, clone a repo (replace <owner>/<repo>):")
                print(f"git clone git@{host}:<owner>/<repo>.git")
        return
    if args.print_keys:
        cfg_path = os.path.expanduser(args.config)
        if not os.path.exists(cfg_path):
            print(f"Config not found at {cfg_path}; run --generate-template first")
            return
        data = yaml.safe_load(Path(cfg_path).read_text(encoding="utf-8"))
        for acct in data.get("accounts", []):
            keypath = os.path.expanduser(acct.get("ssh_key_path"))
            pub = keypath + ".pub"
            if os.path.exists(pub):
                print(f"# {acct.get('id')} public key ({pub}):")
                print(Path(pub).read_text(encoding="utf-8").strip())
            else:
                print(f"Public key missing for {acct.get('id')}: {pub}")
        return
    if args.apply_ssh_config:
        cfg_path = os.path.expanduser(args.config)
        if not os.path.exists(cfg_path):
            print(f"Config not found at {cfg_path}; run --generate-template first")
            return
        data = yaml.safe_load(Path(cfg_path).read_text(encoding="utf-8"))
        ssh_conf_path = os.path.expanduser(data.get("defaults", {}).get("ssh_config_path", "~/.ssh/config"))
        existing = ""
        if os.path.exists(ssh_conf_path):
            existing = Path(ssh_conf_path).read_text(encoding="utf-8")
        new_blocks = []
        for acct in data.get("accounts", []):
            host = acct.get("host_alias") or acct.get("id")
            provider = acct.get("provider")
            hostname = "github.com" if provider == "github" else "gitlab.com" if provider == "gitlab" else provider
            identity = os.path.expanduser(acct.get("ssh_key_path"))
            block = []
            block.append(f"Host {host}")
            block.append(f"    HostName {hostname}")
            block.append("    User git")
            block.append(f"    IdentityFile {identity}")
            block.append("    IdentitiesOnly yes")
            block_text = "\n".join(block) + "\n"
            if block_text.strip() in existing:
                print(f"SSH Host block for {host} already present in {ssh_conf_path}")
                continue
            new_blocks.append(block_text)
        if not new_blocks:
            print("No new SSH host blocks to add")
            return
        if args.dry_run:
            print("--- DRY RUN: SSH blocks to add ---")
            for b in new_blocks:
                print(b)
            return
        backup_path = ssh_conf_path + ".bak"
        if os.path.exists(ssh_conf_path):
            Path(backup_path).write_text(existing, encoding="utf-8")
            print(f"Backed up existing ssh config to {backup_path}")
        with Path(ssh_conf_path).open("a", encoding="utf-8") as f:
            for b in new_blocks:
                f.write("\n" + b)
        print(f"Appended {len(new_blocks)} Host blocks to {ssh_conf_path}")
        return
    if args.apply_gitconfigs:
        cfg_path = os.path.expanduser(args.config)
        if not os.path.exists(cfg_path):
            print(f"Config not found at {cfg_path}; run --generate-template first")
            return
        data = yaml.safe_load(Path(cfg_path).read_text(encoding="utf-8"))
        global_gitconfig = os.path.expanduser(data.get("defaults", {}).get("global_gitconfig", "~/.gitconfig"))
        includes = []
        for acct in data.get("accounts", []):
            gid = acct.get("id")
            repos = acct.get("repos") or []
            if repos:
                for repo in repos:
                    gitcfg_path = os.path.expanduser(f"~/.gitconfig.{gid}.{repo}")
                    if not os.path.exists(gitcfg_path):
                        contents = []
                        contents.append("[user]")
                        contents.append(f"    name = {acct.get('user_name')}")
                        contents.append(f"    email = {acct.get('user_email')}")
                        contents.append("[repo]")
                        contents.append(f"    name = {repo}")
                        Path(gitcfg_path).write_text("\n".join(contents) + "\n", encoding="utf-8")
                        print(f"Wrote per-repo gitconfig {gitcfg_path}")
                    # collect includeIf using repo_base_dirs if provided, otherwise skip
                    repo_dirs = acct.get("repo_base_dirs") or []
                    for rd in repo_dirs:
                        glob = rd.replace("~", os.path.expanduser("~"))
                        # assume repo directory under rd
                        includes.append((os.path.join(glob, repo, "**"), gitcfg_path))
            else:
                gitcfg_path = os.path.expanduser(f"~/.gitconfig.{gid}")
                if not os.path.exists(gitcfg_path):
                    contents = []
                    contents.append("[user]")
                    contents.append(f"    name = {acct.get('user_name')}")
                    contents.append(f"    email = {acct.get('user_email')}")
                    Path(gitcfg_path).write_text("\n".join(contents) + "\n", encoding="utf-8")
                    print(f"Wrote per-account gitconfig {gitcfg_path}")
                repo_dirs = acct.get("repo_base_dirs") or []
                for rd in repo_dirs:
                    glob = rd.replace("~", os.path.expanduser("~"))
                    includes.append((glob, gitcfg_path))
        existing = ""
        if os.path.exists(global_gitconfig):
            existing = Path(global_gitconfig).read_text(encoding="utf-8")
        new_lines = []
        for glob, path in includes:
            inc = f"[includeIf \"gitdir:{glob}\"]\n\tpath = {path}\n"
            if inc in existing:
                print(f"includeIf for {glob} already present")
                continue
            new_lines.append(inc)
        if not new_lines:
            print("No includeIf entries to add to global gitconfig")
            return
        if args.dry_run:
            print("--- DRY RUN: includeIf entries to add ---")
            for l in new_lines:
                print(l)
            return
        backup_path = global_gitconfig + ".bak"
        if os.path.exists(global_gitconfig):
            Path(backup_path).write_text(existing, encoding="utf-8")
            print(f"Backed up existing gitconfig to {backup_path}")
        with Path(global_gitconfig).open("a", encoding="utf-8") as f:
            for l in new_lines:
                f.write("\n" + l)
        print(f"Appended {len(new_lines)} includeIf entries to {global_gitconfig}")
        return
    if args.rewrite_remotes:
        print("rewrite-remotes not implemented yet")
        return
    print("No action specified. Use --generate-template to create a starter config.")

if __name__ == "__main__":
    main()


