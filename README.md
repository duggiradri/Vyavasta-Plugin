<p align="center"><img src="plugins/vyavasta/assets/logo.png" alt="" width="96" height="96"></p>

# Vyavasta for Claude Code and Codex

One plugin for two coding tools, laid out as its own plugin marketplace. With it, Claude Code or Codex on your own computer works with your team’s Vyavasta workspace. What follows says Claude; under Codex it is the same, with Codex in its place.

The plugin is **off in every project** until you send `vyavasta on` there. Off, it sends nothing; only its own commands are answered, and a question about using it is explained to Claude. On:

- **Before Claude changes code**, your request is checked against what your team has said and decided, reading only what you can read in Vyavasta. When something stands in the way, the request is held and you are told who said what. To go ahead anyway, send `Plan it anyway`.
- **When you ask about your team**, the question goes to your own assistant in Vyavasta, the one that answers in its web app’s chat, and Claude gives you its answer. Ask as you would there (“See what Priya is doing”), or speak to it by name (“Vyavasta, what is new?”). The questions of one session are one chat, which you also find in the web app.
- **Summaries for your teammates come from the session itself.** With summaries on (they are on once you turn the project on), your messages and Claude’s reply at the end of each turn are kept as written in this session’s chat in Vyavasta, a chat of your own. A reply can quote code or what a file holds. Nothing else of the conversation is kept. Vyavasta sums the chat up in a sentence or two and files it under a category, exactly as it does for its web app’s chats, and you choose there which categories teammates see. Send `vyavasta summaries off` to stop.
- **Every message gets one line** from Vyavasta saying what was sent, what was not and why, whether it was kept for your summary, and what came of it. The first of a session gives the whole account, for example: `Vyavasta · sent: your message and 2 changed files’ names. Not sent: what the files hold (code sharing is off). Kept in this session’s chat for your summary. · Checked against your team’s record: nothing stands against this change.` The later ones say it in a few words, and leave out what hasn’t changed since: `Vyavasta · sent and kept for your summary · nothing to check`. A question’s line says whether it was kept too.
- **After Claude changes files**, and when it stops, your changed files’ names (git’s own list) are sent, so teammates who read the same repository see your work in progress before it is on GitHub: which files you change, and with code sharing on a short summary of what the change does. The answer to `vyavasta on` says so.
- **When you and a teammate change the same file**, on any branch, committed or not, in a repository nested in your project folder too, or on a branch they pushed to GitHub and haven’t merged, each of you is told once, in one line for each teammate, as a heads-up that holds nothing: before the edit when your message names the file, else right after the edit that made it (work reports go at most every 10 seconds), at the end of the turn, or with your next message. The line names who and how many of your files, for example `Vyavasta: Priya Raman is also changing 15 of your files (src/button.css, src/app.ts, and 13 more). Send “vyavasta --priya” to see them.`, and Claude is given who, which files, on which branch, since when, where their work stands, their commits not pushed yet and what their change does where they share their code, so you can ask it. The teammate is told too: at once in Vyavasta’s web app, and with their next message in their own tool. You are told only of teammates’ work you can already see in Vyavasta (they share their work in progress, and you read the same repository), and again only when another file comes into common, they push a shared file to the main branch (pull first), or one of you is about to push one. Under Codex, whose app doesn’t show a hook’s own line, Codex is told to open its reply with the lines; the note comes after Codex’s next edit with apply_patch, or at the end of the turn, and in Codex’s code mode its model is given the details with your next message, since nothing but a block reaches it after an edit there.
- **See what you have in common**: `vyavasta shared` lists the files you and your teammates both change, and what their changes do; `vyavasta --priya` (a long dash works too, as does a whole name or `vyavasta with Priya Raman`) shows them for one teammate. Add a file, such as `vyavasta --priya src/app.ts`, to see their latest version of it as a diff against yours, where they share their code: your file is never changed, and they are told you looked. Claude does the same when you ask it to.
- **With code sharing on** (off until you turn it on, per project), your uncommitted changes themselves are sent too, so Vyavasta’s check reads the real change. Teammates who can already see this work see a short summary of what the change does, written by Vyavasta, and a teammate who changes the same file can see your latest version of it as a diff against theirs; you are told who looked. If something the team has said stands against the change, Claude is stopped once and you are asked: send `continue` to go on, or `stop` to leave the change where it is. Codex hears of a conflict at its next edit with apply_patch once Vyavasta’s answer brings it (work reports go at most every 10 seconds), and is told to make no more edits and to ask you; nothing forces it to stop. When Codex edits through the shell, or its model edits only through the shell, or it makes no other edit, you are told of the conflict when the turn ends.
- **Teammates.** You reach a teammate with “@” and their name, and everyone else in your workspace with “@team”. A message that starts with one or more of those (“@priya the fix is pushed”, “@priya @sam the fix is pushed”, “@team the release is out”) is sent to each of them by the plugin itself, as you wrote it, before Claude sees it; each of them sees whom else it went to. Mention them anywhere else in a message (“push this, then tell @priya it’s done”), and Claude sends it through Vyavasta once the work is done, in words that say what was done. A message that starts with “@” and a name no teammate has goes to nobody, and its line says so. A teammate and their agent are one address. What you tell them they see in Vyavasta at once, and in their own coding tool with their next message there, at the top of the reply; no agent answers it, and they answer you themselves. To ask a teammate’s agent, which answers only from what you can both already see, send `vyavasta ask`. What teammates send you reaches you the same way: with your next message, on the line under it and at the top of Claude’s reply, and at the start of a session for what came while you were away. Five come at a time at most, each cut short at about 600 characters, and a line says how many more wait: `vyavasta inbox` shows them all, whole. Claude is given them after the plugin’s own instructions, so a full inbox never pushes those out of what Claude Code and Codex pass on.
- **The team’s documents, read when the work needs them.** The documents you may read in Vyavasta (your own, and those teammates share with you) can be listed, searched and read part by part, by you (`vyavasta documents`) and by Claude, for a request such as “compare the refund window in our documents with what the code does”. Claude is given the commands at the start of each session, and again with an answer of Vyavasta’s that drew on a document. Vyavasta decides what you may read on every call, exactly as its web app does. The plugin keeps no copy of a document on your computer; what Claude reads stays in Claude’s own conversation there, as anything it reads does.

The web app stays the place for setup, the record, your team and review. You approve this computer there, and you can disconnect it there (the Coding tools page).

## The first time you use it

- **A banner greets you.** The first session after you install the plugin opens with a banner that names Vyavasta, says where things stand (connected or not, on or off here) and what to try first. It shows once for each tool, again after the plugin is installed again, and once after every update, then with a line on what the new version brought. Removing the plugin does not remove its settings folder, where this computer’s connection is kept: installed again on a connected computer, it says who the computer is connected as and opens no sign-in page, because there is nothing to sign in to. Send `vyavasta sign out` first to start over.
- **A newer plugin is told of once.** In Claude Code, which updates a plugin only when you tell it to, the first session of a project that is on says once for each newer version that it is out, with the two commands that update it. Codex updates the plugin by itself when it starts. A plugin older than the oldest one Vyavasta still works with says so at every session’s start.
- **Sign-in opens by itself.** In the first session after you install the plugin, if this computer isn’t signed in yet, Vyavasta’s Connect page opens in your browser and the session’s first line gives you its code and address. Sign in there if asked, type the code, check the computer’s name, and press **Connect**. Once you approve, your next message finishes connecting, in any project, and says so in one line. The project stays off, and nothing else is sent.
- **A guide comes by email.** The first time you connect a coding tool, Vyavasta emails you a guide to every command. Keep it. The line that says you are connected says so on the sign-in that sent it, and so does the other tool’s first session; a later sign-in says only that the guide is in your email. `vyavasta help` shows the commands any time, and “Email me the guide” on the web app’s Coding tools page sends the email again.
- **One connection serves both tools.** A computer connected through Claude Code is connected for Codex too, and the other way round, so the second tool asks for no code: its first session says who this computer is connected as.
- **Then send `vyavasta on`** in each project you want it in. If you start a session in a project that is on while signed out, sign-in starts by itself there too, once. After `vyavasta sign out`, or once the computer is disconnected in the web app, nothing starts it but `vyavasta sign in`.
- **A sign-in that waits is never started twice.** Until you approve it, every line about it repeats the same code and address and no second page opens. A code lasts 10 minutes, and asking to sign in again says how many are left. Once it has run out, the next sign-in starts afresh with a new code.
- **To find out how to use it,** send `vyavasta` or `vyavasta help`, or ask in your own words, such as `vyavasta how do I sign in` or `vyavasta what can you do`. Help opens with the three steps to start and whether each is done. A question to your team that starts with Vyavasta’s name, such as “Vyavasta, what is Priya working on?”, still goes to your team’s record.
- **Commands take the words people use.** `vyavasta login`, `vyavasta log in` and `vyavasta connect` sign in; `vyavasta logout`, `vyavasta log out` and `vyavasta disconnect` sign out; `vyavasta enable`, `vyavasta turn on`, `vyavasta switch on` and `vyavasta start` turn it on; `vyavasta disable`, `vyavasta turn off` and `vyavasta switch off` turn it off. A colon or a comma after the name (`vyavasta: status`, `Vyavasta, help`) and a no-break space pasted from a web page or an email work as well. `vyavasta` and one word that is none of its commands says so, names the command it nearly is (“Did you mean “vyavasta status”?”), and is never sent to Claude or your team.
- **You can also just ask Claude.** When a short message asks about the plugin itself, such as “How do I sign in to Vyavasta?” or “What does the Vyavasta plugin send?”, the plugin gives Claude the exact phrases to tell you, without sending anything anywhere. A question put to your team, or one that only mentions Vyavasta, gets no such guidance. Claude can’t send these phrases for you: you send them as messages of your own.

## Install in Claude Code (for a tester)

You need Claude Code and git. This repository is open to anyone, so no GitHub account is needed.

1. In a terminal, run this one command. It adds the marketplace and installs the plugin, and run again it changes nothing:

   ```
   claude plugin marketplace add duggiradri/Vyavasta-Plugin && claude plugin install vyavasta@vyavasta
   ```

   Inside Claude Code the same two steps are `/plugin marketplace add duggiradri/Vyavasta-Plugin` and `/plugin install vyavasta@vyavasta`. For a copy on your disk, give its folder instead: `/plugin marketplace add /path/to/vyavasta-plugin`.

2. Start a new session (or run `/reload-plugins`). On a computer that isn’t connected yet, the first session opens Vyavasta’s Connect page in your browser and shows a code: enter it there and press **Connect**.

3. In your project, send:

   ```
   vyavasta on
   ```

   If you aren’t signed in yet, the answer gives the sign-in code again (or starts a new sign-in), and your next message finishes connecting.

## Install in Codex (for a tester)

You need Codex and git. The same script runs under both tools; Codex gets its own hooks file (`plugins/vyavasta/hooks/codex.json`) and description (`plugins/vyavasta/.codex-plugin/plugin.json`).

1. In a terminal, run this one command. It adds the marketplace and installs the plugin, and run again it changes nothing:

   ```
   codex plugin marketplace add duggiradri/Vyavasta-Plugin && codex plugin add vyavasta@vyavasta
   ```

   If the terminal answers that `codex` is not found, Codex may be on your Mac only inside the ChatGPT app. Try the same command through the app’s own copy:

   ```
   /Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex plugin marketplace add duggiradri/Vyavasta-Plugin && /Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex plugin add vyavasta@vyavasta
   ```

   If Codex answers that the marketplace is already added from a different source, you installed the plugin under this repository’s earlier address: run `codex plugin marketplace remove vyavasta`, then the command again.
2. Restart Codex.
3. Approve the plugin’s hooks once: Codex runs no hook until you have reviewed and trusted it. In the terminal, open `/hooks`; in the desktop app, choose **Review hooks**. Codex asks again after each update of the plugin, and it updates the plugin by itself when a new version is out. Until you approve them again, Vyavasta does nothing in Codex: nothing is checked, answered or summed up, and no line from Vyavasta appears under your messages. Three things tell you: Codex answers `vyavasta check` in its own words instead of the plugin’s list; Codex itself says that Vyavasta’s hooks are waiting for your review, when you send one of the plugin’s commands; and the web app shows, when Codex was last heard from on an older version than the newest, a line saying that Codex may be waiting for you to approve the update, on every page until you hide it for that version and beside the computer on the Coding tools page.
4. Start a new session and send any message, such as `vyavasta help`. Codex starts the plugin with your first message in a session, not when the session opens: on a computer that isn’t connected yet, that first message opens Vyavasta’s Connect page in your browser and its answer shows a code. Enter it there and press **Connect**.
5. In your project, send `vyavasta on` as a message of its own.

Codex has no plugin slash commands, so every command is a message. Under Codex the report of changed files also follows shell commands, because Codex often edits files that way. Codex tasks that run in the cloud don’t run a plugin’s hooks, so nothing is checked there. Codex runs the commands its own model starts in a sandbox that can’t write the plugin’s settings folder or reach the internet, so a question Codex puts to Vyavasta by itself has to run outside it. The plugin tells Codex’s model to ask for that (escalated permissions for that one command), and Codex either asks you to approve it or has its own reviewer decide, as you have set it. Run inside the sandbox, the command says what stood in its way there and that it is to be run again outside. When the request is refused, send the question as a message that starts with “Vyavasta,”: the plugin answers a message itself, outside the sandbox.

In Codex’s terminal a name at the very end of a message (“… then tell @priya”) opens Codex’s file picker, and Enter then puts a file in its place: type a space or press Esc before Enter, or put words after the name. Codex shows the answer to one of the plugin’s commands under its heading “Blocked by hook”, with a first line saying that Vyavasta answered it itself and Codex wasn’t sent your message: Codex has no other way to show a hook’s answer to a message, and nothing was refused. `codex exec`, Codex’s run without its terminal, shows nothing a hook says: send the plugin’s commands in Codex’s terminal or app.

To run Codex once without Vyavasta, start it with `codex --disable plugins`. A `-c` override that sets the plugin’s `enabled` to false does not stop its hooks. To stop Vyavasta in one project, send `vyavasta off` there.

When Codex updates the plugin while a session is open, it removes the version that session runs, and that session’s hooks stop without a word: its messages go to Codex as they are, nothing is checked, and a `vyavasta` command reaches Codex’s model unanswered. The questions and messages Codex’s model sends for you keep working, through the copy of the script in the settings folder. Start a new session, and approve Vyavasta’s hooks again when Codex asks.

## Moving from Vyavastha, the plugin's earlier name

Until version 0.5.0 the plugin was called Vyavastha, installed as `vyavastha@vyavastha`. Its marketplace has a new name too, so install it afresh rather than updating:

- In Claude Code: `claude plugin uninstall vyavastha@vyavastha` and `claude plugin marketplace remove vyavastha` in a terminal, then add the marketplace and install `vyavasta@vyavasta` as above, and start a new session.
- In Codex: remove Vyavastha and its marketplace from Codex's plugin list, then add the marketplace and install Vyavasta as above, and approve its hooks again.

Nothing else changes. The computer stays signed in and each project keeps its settings: the plugin goes on using the folder the earlier version kept them in (`~/.config/vyavastha`) for as long as no `~/.config/vyavasta` exists. The phrases you are used to still work (`vyavastha on` is `vyavasta on`), and so do settings given as `VYAVASTHA_HOME`, `VYAVASTHA_SERVER` and the like; where both are set, the `VYAVASTA_` one wins.

## Commands

Each is sent as a message of its own, in either tool; case and a trailing full stop don’t matter. The plugin answers it and the model never sees it. In Claude Code the plugin’s `guide` skill holds the same guidance, so Claude can explain the plugin when you ask it. In Claude Code most are also slash commands (`/vyavasta:on`, `/vyavasta:status`, …), which the plugin answers at once, with no turn of Claude; `ask`, `tell`, `reply`, and searching and reading documents are typed only, because a slash command never passes your words to a shell. On a Claude Code that can’t answer a slash command before it reaches Claude, the command shows Claude its lines to pass on, and lets Claude run that one command of the plugin’s and no other.

`vyavasta help` (or `vyavasta` alone, `vyavasta ?`, or a question such as `vyavasta how do I sign in`) shows what Vyavasta does, the three steps to start with whether each is done, and every command.

Start here
1. Sign in: send `vyavasta sign in`. The sign-in page opens in your browser with a code to enter; once you approve, your next message finishes connecting.
2. Turn it on in this project: send `vyavasta on`. Off is the default in every project.
3. Then just work. Every message gets one line from Vyavasta saying what was sent, and what came of it: the whole account first, then a few words.

Your setup
- `vyavasta status`: whether you’re signed in, and whether this project, code sharing and summaries are on. In the minute after Vyavasta’s server was out of reach or didn’t answer, it says so, and that `vyavasta check` tries it at once.
- `vyavasta check`: tests that git, curl and awk are there, that the settings folder can be written, the server address, that the server answers, sign-in, that this folder is a repository on GitHub that Vyavasta reads for you, that the project, code sharing and summaries are on, and the plugin’s version. Each line says “ok” or the problem and how to fix it.
- `vyavasta off`: stop using Vyavasta in this project. Off keeps your code-sharing and summaries choices.
- `vyavasta sign out`: disconnect this computer. Nothing signs in again by itself until you send `vyavasta sign in`.

See what is shared
- `vyavasta settings`: each setting with its value and how to change it.
- `vyavasta open`, `vyavasta open settings` (also `tools`, `sources`, `team`): opens Vyavasta’s web app, or that page of it, in your browser. Only pages of the Vyavasta server the plugin is set to are ever opened. In Claude Code also `/vyavasta:open` and `/vyavasta:open-settings`.
- `vyavasta share code on` / `vyavasta share code off`: code sharing for this project. Off also deletes what Vyavasta kept of your code.
- `vyavasta summaries on` / `vyavasta summaries off`: summaries for this project: whether your messages and Claude’s replies are kept in this session’s chat and summed up for teammates. On from the moment you turn the project on. A project turned on with an earlier version says so once, on the first line of a session or message, and that first message isn’t kept.
- `vyavasta summary`: your own summaries as Vyavasta keeps them, category by category, each marked “shown to teammates” or “hidden from teammates”, and then what each teammate is working on. It shows what the web app’s Summaries show you. In Claude Code it is also `/vyavasta:summary`.
- `vyavasta sent`: everything sent from this session, as Vyavasta recorded it, oldest first. In Claude Code it is also `/vyavasta:sent`. (Before 0.7.0 this was `vyavasta shared`, which now shows the files you and your teammates both change.)
- `vyavasta chat` / `vyavasta chat open`: this session’s chat in Vyavasta, as a link or opened.
- `vyavasta upload`: opens this session’s chat so you can drop in a file; your next question in this session carries it. A pasted image stays in the coding tool: this command is the way to give Vyavasta a file.

Teammates
- `vyavasta team`: what each teammate is working on, from the summaries they share with the team: each of their categories with its newest summaries and when it was last brought up to date. It shows what the web app’s Summaries show you of your teammates, and nothing of anyone’s chats.
- `vyavasta inbox`: what teammates told you and asked of you that you have not seen yet, numbered. Vyavasta gives 50 at a time, and when more wait, one line says how many. What is new also comes by itself with your next message, each item once: on the line under your message, and at the top of Claude’s reply, five at most and each cut short at about 600 characters (the rest are in `vyavasta inbox`). When some are waiting as a turn ends, a line under it says so, and none of them is marked as read.
- `vyavasta tell <name>: <words>`: tells a teammate something, as you wrote it. They see it in Vyavasta at once, and in their own coding tool with their next message there. No agent answers it. The colon may be a comma, or left out when the name is one word. `vyavasta tell team: <words>` tells everyone else in your workspace, and `vyavasta tell priya, sam: <words>` tells each person named; if one of the names is nobody’s, or two people’s, nothing is sent and the answer says which. When Vyavasta doesn’t take it (it is busy, restarting or out of reach), the answer starts with “Not sent” and says when to send it again; when the message went out but Vyavasta’s answer came too late, was cut off, or was a server failure, the answer says it isn’t known whether it was sent, and to look for it in Vyavasta before sending it again.
- `vyavasta ask <name>: <question>`: asks a teammate’s agent, which answers only from what you can both already see. The colon may be a comma, or left out when the name is one word. A teammate’s agent is Vyavasta answering for them from the team’s record. It is not their Claude Code or Codex, and it does not see their computer. They see what you asked and what it answered, and can answer you themselves.
- `@<name> <words>`: a message that starts with “@” and a teammate’s full or first name tells them something, as you wrote it, the same as `vyavasta tell` (“@priya the fix is pushed”, “@Sam Rivera: I’m changing the billing page today”). The plugin sends it itself, before Claude sees it. The “@” must stand at the start or after a space, and the name must end there: “@priya.txt” or “@priya/notes” is a file, not Priya. `@team <words>` (or `@everyone`) tells everyone else in your workspace, and several names at the start (`@priya @sam <words>`, with spaces or commas between them) tell each of them, in their own conversation with you. The confirmation names everyone it reached. A message that starts with “@” and a name no teammate has reaches nobody: its line says so, and Claude is given it as you wrote it.
- A teammate mentioned anywhere else in a message: “Push this, then tell @priya”, “Run the tests and ping @sam”. Vyavasta’s server finds the mention, and the plugin tells Claude how to send it: Claude does the work first, then sends the message in words of its own that say what was done, and tells you what it sent. Under Codex the command that sends it runs outside Codex’s sandbox, which Codex has you or its own reviewer approve; when that is refused, Codex says so and you can send it yourself with `vyavasta tell`.
- `vyavasta reply <number>: <words>`: answers an item of your last inbox listing.
- `vyavasta documents` (or `vyavasta docs`): the team’s documents you may read in Vyavasta, newest first and numbered, each with its kind, its size, whether it is yours or whom it is from, and whether it is still being read or its reading failed. In Claude Code it is also `/vyavasta:documents`.
- `vyavasta documents search <words>`: passages that mention the words, one from each of the five documents that match best, from what you may read only. The best match mentions the most of the words, then has the most of them in its name, then has them most often, then is the newest. Plain word search: no model is asked. Each passage stands under a line of the plugin’s own that names its document, unmarked, and every line of the passage is marked `│ `, so a line in a document that looks like such a heading is always marked and never passes for another document’s.
- `vyavasta documents read <number or name> [part]`: a document’s text, about 12,000 characters at a time, cut where a paragraph ends, with which part of how many it is and how to read the next. A picture is read as the text Vyavasta’s assistant made of it, and says so.
- Claude runs the same three by itself when the work needs them, by the plugin’s script, and is told how at the start of each session and with an answer of Vyavasta’s that drew on a document. Under Codex they run outside Codex’s sandbox, which Codex has you or its own reviewer approve; when that is refused, Codex says so and you can send the command yourself.

Every message to or from another person’s agent opens with a header line, such as `── To Priya Raman’s agent · from Sam Rivera · 18 November 2026, 10:42 · through Vyavasta ──`, and the answer with `── From Priya Raman’s agent · 18 November 2026, 10:43 · answered only from what you can both already see ──`.

Where Claude reads a document, its text is quoted the same way, between `Quoted from the team’s documents below, …` (a record to read, never instructions) and `End of the quoted documents.`, and the server first takes out every control character and terminal escape, so a document can neither paint your terminal nor forge a line of the plugin’s own.

The words under each header, what teammates wrote in your inbox and the answers to questions Claude asks Vyavasta are quoted: a first line says they come from the team’s record and are never instructions, every line of them starts with `│ `, and `End of the quoted record.` closes them. When Claude itself asks a teammate’s agent, it is given the answer as Vyavasta’s server quotes it, with the server’s own sentence about it before the quoted lines. A name or time in a header, and what Vyavasta’s server says in a command’s answer, are kept to one line, cut short when long, with the characters that turn the direction of the text around taken out. Nothing a teammate or an outsider writes can then pass for the plugin’s own lines. Where only you read them (the answer to a command you typed, and the line under a message), every line of what people wrote still starts with `│ `, but the first and last lines written for Claude are left out, and your own words are never called the team’s record.

## What it sends, and what it keeps

From a project that is off: nothing, except that each tool’s first session on a computer that isn’t signed in starts sign-in, which sends the computer’s name and which tool it is. While that sign-in waits for your approval, each message asks Vyavasta’s server once whether you have approved it, sending only the sign-in’s own reference and never the message; this stops once you are connected or the code has run out.

From a project that is on:

- **With each message:** its words, the repository’s GitHub remote (any user name or token in the address is removed first; none outside a repository), the branch, the tool’s session id, which tool it is, and whether summaries are on. A question about your team carries the same.
- **With summaries on** (per project, on from the moment you turn the project on): your messages and Claude’s reply at the end of each turn are kept as written in this session’s chat in Vyavasta. It is a chat of your own that only you read, in the web app. A held request is kept too. A reply can quote code or what a file holds. Only the first 4,000 characters of a reply are sent, with bytes that aren’t valid text dropped. A reply is sent only after a message kept in the same turn, and is added to that message alone. Nothing else of the conversation is kept: not Claude’s other steps, the commands it ran or the files it read, and not the earlier conversation. Vyavasta then sums the chat up in one or two sentences about the work, never the material itself, and files it under a category: the repository, an initiative, Miscellaneous or Personal. On your Summaries page in the web app you choose which categories teammates see (Personal stays hidden until you turn it on). The summaries appear on that page, on the Team page and in answers about what you are working on. Deleting the chat in the web app deletes its summary with it.
- **Never kept:** the plugin’s own commands (`vyavasta …`, which are never sent at all) and these answers to the plugin’s own questions: `Plan it anyway`, `continue`, `continue anyway`, `go on` and `stop` (case, spacing and a closing full stop, exclamation or question mark don’t matter).
- **With summaries off:** nothing you write in this project, and none of Claude’s replies, is kept or summed up for teammates. No reply is sent, and `vyavasta sent` shows that a request was checked, never its words. A question about your team is still answered by Vyavasta’s assistant. It stays in your chat there, where you can delete it.
- **A question about your team:** its words and the answer are a chat of your own in Vyavasta, exactly as if you had asked in the web app. Nobody else sees it. It is summed up for teammates only with summaries on. A message is taken for such a question when it speaks to Vyavasta by name, is about the team, about what was said or decided, or about what was written in your chat tools or your mail (“check my messages in Slack”), or when it names a teammate. A short message that goes on from an answer Vyavasta just gave in the same session is one too: it speaks of someone the answer was about (“did he push it?”), asks for the same again (“check now”), or is a bare question (“why?”). Anything else goes to Claude, which can still ask Vyavasta by itself.
- **With each message and after edits:** your changed files’ names: for each, its path, git’s status (added, changed, deleted, renamed) and line counts (none for a new file that looks like a key, is machine-written or is over 1 MB, which isn’t read at all). Without code sharing, these reports **never carry what a file holds.**
- **With code sharing on, also:** one unified diff of your working tree against your GitHub copy (where your branch last matched its upstream, else origin’s default branch, else your last commit): your edits, new files git doesn’t ignore, deleted and renamed files, and commits not yet pushed. It is sent with each message, and after edits when it changed since it was last sent. Vyavasta’s check reads it; teammates who can already see this work see a short summary of what the change does, and a teammate who changes the same file can see your latest version of it as a diff, you told who looked. What is sent is chosen file by file from git’s own list, by each file’s exact name, and a file the plugin can’t vouch for is left out rather than sent. Never sent, each named in the list of what was left out with its reason:
  - files git ignores (they are never even listed);
  - files that look like keys or credentials, in any letter case and in any folder, even when committed, and a file renamed from or to such a name: `.env` and `.env.*`, `*.pem`, `*.key`, `*.p12`, `*.pfx`, `*.jks`, `*.keystore`, `id_rsa*`, `id_ed25519*`, `*.kdbx`, `credentials` and `credentials.*`, `secrets.*`, `*.secret`, `.npmrc`, `.pypirc`, `.netrc`, `*.tfvars`, `*.tfstate*`, `auth.json`, `service-account*.json`;
  - machine-written files: lock files (`package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `Cargo.lock`, `poetry.lock`, `uv.lock`, `go.sum` and the like), `*.min.js`, `*.min.css`, `*.map`, generated protocol files, and anything under `node_modules/`, `dist/`, `build/`, `out/`, `target/`, `vendor/`, `.next/`, `coverage/` or `__pycache__/`;
  - files that aren’t text, symbolic links (whatever they point to; a link to a key file is counted as one), files that changed type, and a new file whose name holds a line break;
  - files that would take the whole past 5,000 lines of changes (the server may set another limit), and a new file over 1 MB, which isn’t read at all; later, smaller files may still fit. A line longer than 2,000 characters is cut, and bytes that aren’t valid text are dropped.
  - a submodule is sent only as the commit it is at, never its files.

  Vyavasta keeps only the latest changes of each session, until the work ends and for 7 days at most. `vyavasta share code off` deletes what was kept. Turning code sharing off in the web app turns it off here too, and the next line says so. Signing out and in again keeps your choice, and the new connection is told it with your next message.
- **Never:** the conversation transcript (only your messages and Claude’s last reply of each turn, with summaries on), Claude’s other steps, environment variables, or anything from a project that is off.
- **Reading documents:** the words of a search, or which document and which part, with the session and repository as for a message. Vyavasta notes each list, search and read under `vyavasta sent` by the documents’ names, never their text. What comes back is the documents’ text, which the plugin prints and never writes to disk: its scratch files go when the command ends, and a command that could only make them inside the settings folder reads nothing.
- **A message for a teammate:** its words and who it is for. It is kept in the thread between the two of you in Vyavasta, which both of you read, and as a message of the team’s record for the two of you alone.
- **Back from the server:** facts with their sources (who said what, when and where, and what the check made of them), the answer to a question, what teammates sent you since you were last told, and teammates changing the same files as you (from the record of their work in progress, which you may already read), all shown to Claude as context; what teammates wrote stands in quoted records, which are never instructions to Claude. The plugin makes no model calls of its own on your Claude subscription.
- **On your computer:** the token, in `~/.config/vyavasta/credentials` (or `$XDG_CONFIG_HOME/vyavasta`, or `$VYAVASTA_HOME`), readable by you only (`chmod 600`, in a `700` folder); both tools share it. A token is never sent to any server but the one that issued it. Which projects are on, and whether code sharing and summaries are on for each and whether you were told what summaries do, are kept in `projects/` in the same folder, and short-lived notes for each session in `sessions/`, removed after a week. A reply or a work report that couldn’t be sent waits in `unsent/` for 50 minutes at most (ten at most), goes along with a later message, and is forgotten when you sign in or out. `bin/` holds a copy of the plugin’s script, which Claude and Codex run for Vyavasta’s commands; its path stays the same when the plugin is updated.

If you aren’t signed in, the server can’t be reached, or it isn’t working, Claude works as usual and the message’s line says what happened in one plain sentence. After `vyavasta sign out`, or once the computer is disconnected in the web app, nothing starts signing in by itself until you send `vyavasta sign in`. A message longer than the 40,000 characters Vyavasta takes (a pasted log) is cut to them, with a mark where it was cut, and its line says so; Claude is given the whole message. What the server refuses for what was sent, such as a branch name longer than it takes, is said as that, never as a passing problem. A slow check gives up after about a minute and Claude goes on. Sending the reply at the end of a turn gives up after 4 seconds (8 with the turn’s work report), and a slow answer to a question is handed over after about a minute and left in your chat in Vyavasta. So is the answer to a question that was asked when a later wait for it fails, as it does while the server restarts: the line says the question was asked and where its answer will be, and Claude answers by itself meanwhile. A question whose own call went out and got no answer, as a server too busy to answer may still have taken it, is told as one that may have been asked, with where its answer will be if it was. For ten minutes after a call went unanswered, each call that may take 4 seconds or longer first asks Vyavasta’s quick question, which the server answers at once even when it is busy: a server that only answered late is still asked to check every message, and one that takes calls and answers none costs one wait for that question, at a session’s start and the end of a turn as at a message. A server out of reach, or one that leaves the quick question unanswered, isn’t tried again for a minute by anything that runs by itself: a session starts at once and says so, each message’s line says so, and the end of a turn keeps its reply and the files’ names to go along with a later message. A kept reply or report that a slow server doesn’t take in time waits a minute before it goes along again, so it holds up no more than one message a minute. `vyavasta status` says when Vyavasta isn’t being tried, and `vyavasta check` tries it at once. The plugin’s curl reads none of your own curl settings and follows no redirect. The plugin never writes git’s own index or takes its lock, so your git commands and Claude’s never collide with it; it never runs a program a repository’s own settings name to watch its files, as its hooks, or as its filters (filters you set up for every repository, such as git-lfs’s, work as usual), and it reads no new file that is a link, a device, or larger than 1 MB; and it opens a page in your browser only when the page is on your Vyavasta server’s own address, printing any other for you to open yourself. In a project that is off it looks only at the message itself, never the folder it was sent from: whether it starts with “vyavasta” and, for a message of 2,000 characters or fewer, whether it names Vyavasta. Any other message isn’t read at all.

## Why a shell script

Hooks are plain POSIX `sh` using only `git`, `curl` and `awk`. Claude Code runs a command hook through `sh` on macOS and Linux, and through Git Bash on Windows. The plugin needs git anyway, and on Windows git comes as Git for Windows, which brings Git Bash, curl and awk with it. Claude Code itself installs no Node.js or Python, so this script assumes neither, and it doesn’t use jq. Without Git for Windows, Claude Code runs hooks in PowerShell and these hooks won’t run. Claude still works then, but nothing is checked or shared.

## Choosing the server

By default the plugin talks to `https://vyavasta.com`. To use another server:

- set `VYAVASTA_SERVER` in the shell you start Claude Code from, for example `export VYAVASTA_SERVER=https://vyavasta.example.com`, or
- save one for every session: `sh <plugin folder>/scripts/vyavasta.sh use-server https://vyavasta.example.com` (run `use-server` with no address to go back to the default).

Only `https://` addresses are accepted, apart from `http://localhost` and `http://127.0.0.1` for testing.

## Local testing

To run Vyavasta in demo mode on this Mac and point the plugin at it:

1. Start the server from the Vyavasta project folder (the web app must be built once with `cd frontend && npm run build`):

   ```
   VYAVASTA_DATA_DIR=/tmp/vyavasta-demo PYTHONPATH=src .venv/bin/python -m mas_stealth.web_cli --demo --port 8804
   ```

2. Open `http://127.0.0.1:8804`, create an account (the demo shows the sign-in email on screen), and connect GitHub and Slack in Sources. The demo repository is `northwind/customer-platform`.

3. Get a clone whose remote names that repository:

   ```
   mkdir customer-platform && cd customer-platform && git init
   git remote add origin https://github.com/northwind/customer-platform.git
   ```

4. Add this folder as a marketplace, install the plugin, and start Claude Code with the server set:

   ```
   claude plugin marketplace add /path/to/vyavasta-plugin
   claude plugin install vyavasta@vyavasta
   VYAVASTA_SERVER=http://127.0.0.1:8804 claude
   ```

   Then send `vyavasta on` and approve the code in the browser. Ask for something like “Remove customer_plan from the API response”. The demo has no model, so it holds nothing, but Claude is shown what the team’s record says about the request.

## The logo

The mark is a seal of red wax pressed with the Devanagari letter व, the same drawing as in Vyavasta’s web app: `plugins/vyavasta/assets/logo.svg`, with `logo.png` (512 by 512) and `composer-icon.png` (64 by 64, the letter drawn for small sizes, without the ring) made from it. Codex shows them in its plugin list and composer, with the brand colour #9A2219, as `.codex-plugin/plugin.json` names them. Claude Code shows no logo for a plugin from a private marketplace, so its `plugin.json` names none.

## Tests

```
python3 -m pytest tests -q -n 8                                     # the hook script against a fake server
python3 tests/end_to_end.py --project /path/to/MAS_Stealth --port 8804   # the whole loop against a demo server
claude plugin validate . && claude plugin validate plugins/vyavasta
```

`tests/test_hooks.py` runs each test under `sh` and, where it is installed, `dash` (Ubuntu’s `sh`). `tests/end_to_end.py` starts the demo server on its own port with a scratch data folder, pairs the plugin’s script with it as a developer would, feeds each hook the JSON Claude Code sends, checks that a teammate’s account sees the work, and then stops the server.
