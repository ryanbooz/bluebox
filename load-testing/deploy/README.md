# Running the load generator as a systemd service

Running under systemd lets the generator survive logout, restart on crash, and stream logs to anyone with terminal access — including browser-based terminals like the AWS console — without needing `tmux` or `screen`.

## One-time setup

Before installing the service, make sure the repo is checked out on the VM, `.env` is configured, and the Python environment is built once:

```bash
cd ~/bluebox/load-testing
cp .env.example .env
$EDITOR .env                  # set DB_HOST, DB_PASSWORD, etc.
uv sync                       # creates .venv/ — only needed once
uv run bluebox-load check     # confirms DB connectivity before the service runs
```

`uv` itself needs to be installed for the user that will run the service. The standard installer (`curl -LsSf https://astral.sh/uv/install.sh | sh`) puts it at `~/.local/bin/uv`.

## Install the service

Open [bluebox-load.service](bluebox-load.service) and edit the three lines marked `EDIT:`:

- `User=` / `Group=` — the Linux user that owns the checked-out repo
- `WorkingDirectory=` — absolute path to the `load-testing/` directory
- `ExecStart=` — absolute path to `uv` (run `which uv` to find it)

Then copy it into place and enable it:

```bash
sudo cp deploy/bluebox-load.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now bluebox-load
```

`--now` starts the service immediately; `enable` makes it come back after a reboot.

## Day-to-day operations

```bash
sudo systemctl status bluebox-load     # is it running? last few log lines
sudo systemctl restart bluebox-load    # after editing .env
sudo systemctl stop bluebox-load       # graceful shutdown (drains workers)
sudo systemctl start bluebox-load

journalctl -u bluebox-load -f          # tail logs (Ctrl-C to detach — no tmux required)
journalctl -u bluebox-load --since "1 hour ago"
journalctl -u bluebox-load -p err      # errors only
journalctl -u bluebox-load -n 200      # last 200 lines, no follow
```

`journalctl -f` is the tmux replacement: multiple co-workers can each run their own follow session from any terminal — SSH, browser console, anywhere — and Ctrl-C exits cleanly without disturbing the running service or anyone else's session.

## Changing configuration

Edit `.env` in the `load-testing/` directory, then `sudo systemctl restart bluebox-load`. The runner will re-read the file on next start. You can also iterate on scenario code the same way: pull, then restart.

## Uninstall

```bash
sudo systemctl disable --now bluebox-load
sudo rm /etc/systemd/system/bluebox-load.service
sudo systemctl daemon-reload
```

## Per-user alternative (no sudo)

If you'd rather run the service as a regular user without root — useful on shared VMs where multiple people each run their own copy — install as a user unit instead:

```bash
mkdir -p ~/.config/systemd/user
cp deploy/bluebox-load.service ~/.config/systemd/user/
# Remove the User=/Group= lines from the copy — user units already run as you.
systemctl --user daemon-reload
systemctl --user enable --now bluebox-load
loginctl enable-linger $USER          # keep the service running after logout
```

Then drop `sudo` and add `--user` to all the management commands above (`journalctl --user -u bluebox-load -f`, etc.).
