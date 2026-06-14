import { spawn } from 'node:child_process';
import path from 'path';
import { pathToFileURL } from 'url';

export const runtime = 'nodejs';

// Opens the offline snapshot in the OS default browser as a real file:// URL.
// Browsers refuse to navigate from an http:// page to file://, so the "View HTML"
// button asks the running server to launch it instead. The resulting tab is a
// plain local file, so it keeps working after the dev server shuts down.
//
// Path comes from process.cwd() at request time, so renaming the project folder
// (e.g. A_StudyBuddy -> a_StudyBuddy) needs no change here.
const STATIC_FILE = path.join(process.cwd(), 'public', 'studybuddy.html');

export async function POST() {
  try {
    const fileUrl = pathToFileURL(STATIC_FILE).href;
    const platform = process.platform;
    const cmd =
      platform === 'win32' ? 'cmd' : platform === 'darwin' ? 'open' : 'xdg-open';
    const args = platform === 'win32' ? ['/c', 'start', '', fileUrl] : [fileUrl];

    spawn(cmd, args, { stdio: 'ignore', shell: false, detached: true }).unref();
    return Response.json({ ok: true, url: fileUrl });
  } catch (err) {
    const msg = err instanceof Error ? err.message : 'open failed';
    return Response.json({ error: msg }, { status: 500 });
  }
}
