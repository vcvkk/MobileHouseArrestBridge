#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
MobileHouseArrest Bridge CLI (mha-cli)
Professional interface for interacting with iOS MobileHouseArrest sandbox escape daemon.
"""

from __future__ import annotations

import argparse
import base64
import datetime
import json
import os
import socket
import sys
from typing import Any, Dict, List, Optional

VERSION = "1.1.0"
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8080


class Colors:
    """ANSI color helpers with automatic TTY detection."""
    ENABLED = sys.stdout.isatty()

    RESET = "\033[0m" if ENABLED else ""
    BOLD = "\033[1m" if ENABLED else ""
    DIM = "\033[2m" if ENABLED else ""
    CYAN = "\033[36m" if ENABLED else ""
    GREEN = "\033[32m" if ENABLED else ""
    YELLOW = "\033[33m" if ENABLED else ""
    RED = "\033[31m" if ENABLED else ""
    MAGENTA = "\033[35m" if ENABLED else ""
    BLUE = "\033[34m" if ENABLED else ""


def format_bytes(size: int) -> str:
    """Format bytes into human readable format."""
    for unit in ['B', 'KB', 'MB', 'GB']:
        if size < 1024.0:
            return f"{size:.1f} {unit}" if unit != 'B' else f"{size} {unit}"
        size /= 1024.0
    return f"{size:.1f} TB"


class MHAClient:
    """Network client communicating with the iOS MobileHouseArrest daemon."""

    def __init__(self, host: str = DEFAULT_HOST, port: int = DEFAULT_PORT, timeout: float = 10.0):
        self.host = host
        self.port = port
        self.timeout = timeout

    def send(self, command: str) -> Dict[str, Any]:
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.settimeout(self.timeout)
                s.connect((self.host, self.port))
                s.sendall(command.encode("utf-8"))

                buffer = bytearray()
                while True:
                    chunk = s.recv(65536)
                    if not chunk:
                        break
                    buffer.extend(chunk)

                if not buffer:
                    return {"status": "error", "error": "Empty response received from iOS daemon"}

                return json.loads(buffer.decode("utf-8"))
        except ConnectionRefusedError:
            return {
                "status": "error",
                "error": f"Connection refused to {self.host}:{self.port}. Ensure the iOS app is running and 'iproxy {self.port} {self.port}' is active."
            }
        except socket.timeout:
            return {"status": "error", "error": f"Request timed out after {self.timeout} seconds"}
        except Exception as e:
            return {"status": "error", "error": f"Socket communication error: {str(e)}"}


# -----------------------------------------------------------------------------
# Command Handlers
# -----------------------------------------------------------------------------

def cmd_ping(client: MHAClient, args: argparse.Namespace) -> int:
    res = client.send("PING")
    if res.get("status") != "success":
        print(f"{Colors.RED}[!] Error: {res.get('error')}{Colors.RESET}", file=sys.stderr)
        return 1

    if args.json:
        print(json.dumps(res, indent=2))
        return 0

    data = res.get("data", {})
    print(f"{Colors.GREEN}[+] Connected to MobileHouseArrest Daemon v{data.get('server_version', '1.0')}{Colors.RESET}")
    print(f"  {Colors.BOLD}Device Model:{Colors.RESET}   {data.get('device_model')}")
    print(f"  {Colors.BOLD}iOS Version:{Colors.RESET}    {data.get('os_version')}")
    print(f"  {Colors.BOLD}Process:{Colors.RESET}        {data.get('process_name')} (PID: {data.get('pid')})")
    return 0


def cmd_apps_list(client: MHAClient, args: argparse.Namespace) -> int:
    res = client.send("APPS")
    if res.get("status") != "success":
        print(f"{Colors.RED}[!] Error enumerating applications: {res.get('error')}{Colors.RESET}", file=sys.stderr)
        return 1

    data = res.get("data", {})
    apps: List[Dict[str, Any]] = data.get("apps", [])

    # Filter
    if args.user_only:
        apps = [a for a in apps if a.get("type") == "User"]
    elif args.system_only:
        apps = [a for a in apps if a.get("type") in ("System", "Hidden")]

    if args.filter:
        pattern = args.filter.lower()
        apps = [a for a in apps if pattern in a.get("name", "").lower() or pattern in a.get("bundle_id", "").lower()]

    if args.json:
        print(json.dumps(apps, indent=2))
        return 0

    if not apps:
        print(f"{Colors.YELLOW}[*] No matching applications found.{Colors.RESET}")
        return 0

    print(f"{Colors.BOLD}{'NAME':<28} {'BUNDLE IDENTIFIER':<38} {'TYPE':<8} {'CONTAINER STATUS'}{Colors.RESET}")
    print("-" * 105)
    for app in apps:
        name = (app.get("name") or "Unknown")[:26]
        bundle_id = (app.get("bundle_id") or "")[:36]
        app_type = app.get("type") or "User"
        has_container = bool(app.get("container_path"))

        status_str = f"{Colors.GREEN}Active{Colors.RESET}" if has_container else f"{Colors.DIM}No Container{Colors.RESET}"
        type_color = Colors.CYAN if app_type == "User" else Colors.MAGENTA

        print(f"{name:<28} {bundle_id:<38} {type_color}{app_type:<8}{Colors.RESET} {status_str}")

    print(f"\n{Colors.DIM}Total: {len(apps)} applications displayed.{Colors.RESET}")
    return 0


def cmd_container_activate(client: MHAClient, args: argparse.Namespace) -> int:
    is_group = 1 if args.group else 0
    cmd = f"ACTIVATE {args.class_id} {is_group} {args.identifier}"
    res = client.send(cmd)

    if res.get("status") != "success":
        print(f"{Colors.RED}[!] Activation failed: {res.get('error')}{Colors.RESET}", file=sys.stderr)
        return 1

    if args.json:
        print(json.dumps(res, indent=2))
        return 0

    data = res.get("data", {})
    print(f"{Colors.GREEN}[+] Container successfully activated & sandbox extension consumed!{Colors.RESET}")
    print(f"  {Colors.BOLD}Target Identifier:{Colors.RESET} {data.get('identifier')}")
    print(f"  {Colors.BOLD}Container Class:{Colors.RESET}   {data.get('class')}")
    print(f"  {Colors.BOLD}Resolved Path:{Colors.RESET}     {Colors.CYAN}{data.get('path')}{Colors.RESET}")
    return 0


def cmd_fs_ls(client: MHAClient, args: argparse.Namespace) -> int:
    cmd = f"LS {args.path}"
    res = client.send(cmd)

    if res.get("status") != "success":
        print(f"{Colors.RED}[!] Failed to list directory: {res.get('error')}{Colors.RESET}", file=sys.stderr)
        return 1

    if args.json:
        print(json.dumps(res, indent=2))
        return 0

    data = res.get("data", {})
    items: List[Dict[str, Any]] = data.get("items", [])

    if not args.all:
        items = [i for i in items if not i.get("name", "").startswith(".")]

    items.sort(key=lambda x: (not x.get("is_dir", False), x.get("name", "").lower()))

    print(f"{Colors.BOLD}Listing for:{Colors.RESET} {data.get('path')}\n")
    if args.long:
        print(f"{Colors.BOLD}{'TYPE':<6} {'SIZE':<12} {'MODIFIED':<20} {'NAME'}{Colors.RESET}")
        print("-" * 75)
        for item in items:
            is_dir = item.get("is_dir", False)
            type_str = f"{Colors.BLUE}DIR{Colors.RESET}" if is_dir else "FILE"
            size_str = format_bytes(item.get("size", 0)) if not is_dir else "-"
            mod_ts = float(item.get("modified", 0))
            mod_str = datetime.datetime.fromtimestamp(mod_ts).strftime('%Y-%m-%d %H:%M:%S') if mod_ts else "-"
            name_str = f"{Colors.BLUE}{Colors.BOLD}{item.get('name')}/{Colors.RESET}" if is_dir else item.get("name")

            print(f"{type_str:<15} {size_str:<12} {mod_str:<20} {name_str}")
    else:
        for item in items:
            if item.get("is_dir"):
                print(f"{Colors.BLUE}{Colors.BOLD}{item.get('name')}/{Colors.RESET}")
            else:
                print(item.get("name"))

    print(f"\n{Colors.DIM}{len(items)} items total.{Colors.RESET}")
    return 0


def cmd_fs_cat(client: MHAClient, args: argparse.Namespace) -> int:
    cmd = f"READ {args.path}"
    res = client.send(cmd)

    if res.get("status") != "success":
        print(f"{Colors.RED}[!] Failed to read file: {res.get('error')}{Colors.RESET}", file=sys.stderr)
        return 1

    content_b64 = res.get("data", {}).get("content_b64", "")
    content = base64.b64decode(content_b64)
    sys.stdout.buffer.write(content)
    return 0


def cmd_fs_pull(client: MHAClient, args: argparse.Namespace) -> int:
    cmd = f"READ {args.remote_path}"
    res = client.send(cmd)

    if res.get("status") != "success":
        print(f"{Colors.RED}[!] Download failed: {res.get('error')}{Colors.RESET}", file=sys.stderr)
        return 1

    content_b64 = res.get("data", {}).get("content_b64", "")
    raw_data = base64.b64decode(content_b64)

    local_path = args.local_path or os.path.basename(args.remote_path.rstrip("/")) or "downloaded_file"
    with open(local_path, "wb") as f:
        f.write(raw_data)

    print(f"{Colors.GREEN}[+] Downloaded {format_bytes(len(raw_data))} -> {local_path}{Colors.RESET}")
    return 0


def cmd_fs_push(client: MHAClient, args: argparse.Namespace) -> int:
    if not os.path.isfile(args.local_path):
        print(f"{Colors.RED}[!] Local file '{args.local_path}' does not exist.{Colors.RESET}", file=sys.stderr)
        return 1

    with open(args.local_path, "rb") as f:
        data = f.read()

    b64_str = base64.b64encode(data).decode("utf-8")
    cmd = f"WRITE {args.remote_path}\n{b64_str}"
    res = client.send(cmd)

    if res.get("status") != "success":
        print(f"{Colors.RED}[!] Upload failed: {res.get('error')}{Colors.RESET}", file=sys.stderr)
        return 1

    print(f"{Colors.GREEN}[+] Successfully uploaded {format_bytes(len(data))} to {args.remote_path}{Colors.RESET}")
    return 0


# -----------------------------------------------------------------------------
# Entry Point & CLI Parser
# -----------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="mha-cli",
        description=f"{Colors.BOLD}MobileHouseArrest Remote Management Client v{VERSION}{Colors.RESET}\n"
                    "Automate sandbox escape operations and file management over USB.",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    parser.add_argument("--host", default=DEFAULT_HOST, help="Daemon host address (default: 127.0.0.1)")
    parser.add_argument("-p", "--port", type=int, default=DEFAULT_PORT, help="Daemon TCP port (default: 8080)")
    parser.add_argument("-t", "--timeout", type=float, default=10.0, help="Socket timeout in seconds (default: 10)")
    parser.add_argument("--json", action="store_true", help="Output results in JSON format")

    subparsers = parser.add_subparsers(dest="subcommand", title="Command Categories", metavar="<command>")

    # ping
    p_ping = subparsers.add_parser("ping", help="Check daemon connection and get device metadata")
    p_ping.set_defaults(func=cmd_ping)

    # apps
    p_apps = subparsers.add_parser("apps", help="Installed applications management")
    apps_sub = p_apps.add_subparsers(dest="apps_action", metavar="<action>")
    
    p_apps_list = apps_sub.add_parser("list", help="Enumerate all installed applications and their container paths")
    p_apps_list.add_argument("-u", "--user-only", action="store_true", help="Show only user-installed apps")
    p_apps_list.add_argument("-s", "--system-only", action="store_true", help="Show only system apps")
    p_apps_list.add_argument("-f", "--filter", help="Search filter by name or bundle identifier")
    p_apps_list.set_defaults(func=cmd_apps_list)

    # container
    p_container = subparsers.add_parser("container", help="Direct container escape operations")
    cont_sub = p_container.add_subparsers(dest="container_action", metavar="<action>")
    
    p_cont_act = cont_sub.add_parser("activate", help="Acquire and consume sandbox extension for a container")
    p_cont_act.add_argument("-c", "--class-id", type=int, default=2, choices=[2, 7, 13], help="Container class (2: AppData, 7: AppGroup, 13: SystemGroup)")
    p_cont_act.add_argument("-g", "--group", action="store_true", help="Designate identifier as App Group")
    p_cont_act.add_argument("identifier", help="Bundle ID or App Group identifier")
    p_cont_act.set_defaults(func=cmd_container_activate)

    # fs
    p_fs = subparsers.add_parser("fs", help="Remote filesystem operations")
    fs_sub = p_fs.add_subparsers(dest="fs_action", metavar="<action>")

    p_fs_ls = fs_sub.add_parser("ls", help="List remote directory entries")
    p_fs_ls.add_argument("-l", "--long", action="store_true", help="Detailed listing with size and dates")
    p_fs_ls.add_argument("-a", "--all", action="store_true", help="Include hidden entries (dotfiles)")
    p_fs_ls.add_argument("path", help="Absolute path to list")
    p_fs_ls.set_defaults(func=cmd_fs_ls)

    p_fs_cat = fs_sub.add_parser("cat", help="Print remote file contents to stdout")
    p_fs_cat.add_argument("path", help="Absolute path to read")
    p_fs_cat.set_defaults(func=cmd_fs_cat)

    p_fs_pull = fs_sub.add_parser("pull", help="Download file from iOS device to PC")
    p_fs_pull.add_argument("remote_path", help="Remote path on iOS")
    p_fs_pull.add_argument("local_path", nargs="?", help="Local destination file path")
    p_fs_pull.set_defaults(func=cmd_fs_pull)

    p_fs_push = fs_sub.add_parser("push", help="Upload file from PC to iOS device")
    p_fs_push.add_argument("local_path", help="Local source path")
    p_fs_push.add_argument("remote_path", help="Remote destination path on iOS")
    p_fs_push.set_defaults(func=cmd_fs_push)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    if not hasattr(args, "func"):
        parser.print_help()
        return 0

    client = MHAClient(host=args.host, port=args.port, timeout=args.timeout)
    return args.func(client, args)


if __name__ == "__main__":
    sys.exit(main())
