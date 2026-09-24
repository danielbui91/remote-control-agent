# Recreating Balack on another machine

> **If the target machine cannot clone this repo, use [REBUILD-PROMPT.md](REBUILD-PROMPT.md)
> instead.** That prompt is self-contained — it carries `mac.sh` and Balack's system
> prompt in full, so the machine builds its own copy in its own repo and needs no
> access to this one. The route below is only the shortcut for machines that *can*
> clone, where copying is quicker than rebuilding.

Paste the block below into a fresh Claude Code session on the target machine. It
works under any Claude account — Balack needs no API key and no Anthropic
credential of his own.

**Repo access is required.** The scripts are ~700 lines with several
non-obvious fixes in them; a session told to "rebuild from a description" will
produce something that looks right and drops clicks. Before running this on a
fleet machine, make sure that machine can clone the repo — add the account as a
collaborator, or make the repo public.

**What is copied exactly, and what is not.** The system prompt is copied
verbatim from `agents/balack.template.md`. Four things are per-machine and get
filled in during setup: the script paths, which app owns the terminal, and the
display geometry. Copying those from another machine is the one way to get a
Balack that is subtly and confusingly wrong.

---

```
Set up "Balack", a desktop-automation subagent, on this machine. Work through
these in order, then report. Do not skip the verification steps.

1. Clone https://github.com/danielbui91/remote-control-agent into the usual
   code directory on this machine.
   If it is private and you cannot reach it, STOP and say so. Do not rebuild
   mac.sh or win.ps1 from scratch — they contain fixes you will not guess, and
   a near-miss version fails in ways that look like permissions problems.

2. macOS: chmod +x mac.sh
   Windows: if scripts are blocked, Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

3. Detect the OS. macOS uses mac.sh; Windows uses win.ps1. Record the absolute
   path of the one this machine will use, and of the other one.

4. macOS only — find which app owns this terminal, because that is what needs
   the permissions (not python, not the script):
       pid=$$; while [ "$pid" -ne 1 ]; do ps -o pid=,ppid=,comm= -p "$pid"; \
         pid=$(ps -o ppid= -p "$pid"|tr -d ' '); done
   The last entry is the app. The human must grant it BOTH "Accessibility" and
   "Screen Recording" under System Settings > Privacy & Security, then restart
   it. Nothing below step 7 will work until they do. You cannot do this for
   them; say clearly that it is needed.

5. Run the displays command and keep the exact output:
       ./mac.sh displays        (or: .\win.ps1 displays)

6. Write ~/.claude/agents/balack.md from agents/balack.template.md in the repo.
   Replace these four placeholders and change NOTHING else — the rest of that
   prompt is deliberate:
       {{MAC_SH_PATH}}   absolute path to mac.sh
       {{WIN_PS1_PATH}}  absolute path to win.ps1
       {{TERMINAL_APP}}  the app from step 4 (macOS), else "the terminal app"
       {{DISPLAYS}}      the lines from step 5, indented two spaces, one per line
   Two traps:
   - The `description:` line must not contain a colon followed by a space. YAML
     treats that as a mapping and the frontmatter fails to parse, and a subagent
     with broken frontmatter does not warn — it just never appears.
   - Keep `tools: Bash, Read`. Balack drives the desktop; he does not edit code.

7. Verify he loads. Agent definitions are read at session start, so he will NOT
   appear in your current session — check with a new one:
       claude --agent balack --print "Reply with only the word READY."

8. Once the human confirms the permissions from step 4, smoke test him:
       echo "Open the calculator, compute 9 times 6, and report what the display
       shows. Say which approach worked and which you tried first." \
         | claude --agent balack --print --allowedTools Bash Read
   Pass the prompt on stdin as shown. --allowedTools is variadic and will
   swallow a prompt given as a trailing argument.
   A good answer reports 54, says it tried named controls first, found the
   buttons unlabelled, and fell back to keystrokes. If it reports 54 without
   having verified on screen, the prompt was not copied correctly.

Report at the end: the OS, the two script paths, the terminal-owning app, the
display geometry you recorded, whether steps 7 and 8 passed, and exactly what
the human still needs to click.
```

---

## Checking it afterwards

```bash
diff <(sed 's/{{.*}}/X/' ~/.claude/agents/balack.md) \
     <(sed 's/{{.*}}/X/' agents/balack.template.md)
```

Anything beyond the four substituted regions means the prompt was edited rather
than filled in. That matters more than it looks — the escalation order and the
stop conditions are the parts that keep him from clicking something he
shouldn't.
