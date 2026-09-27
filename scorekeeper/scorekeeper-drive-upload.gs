/**
 * Volleyball scorekeeper → Google Drive receiver
 *
 * Deployed once as a Google Apps Script "Web app" in your Google account.
 * When a match ends, the scorekeeper app (wherever you host volleyball-scorekeeper.html) POSTs
 * the match file here, and this saves it into the Drive folder below.
 *
 * What it can do: create/update .json files in ONE folder. Nothing else —
 * it never reads, lists or deletes anything else in Drive.
 *
 * Deploy: Deploy → New deployment → type "Web app" →
 *         Execute as: Me   ·   Who has access: Anyone
 */

const FOLDER_NAME = 'Volleyball Matches – Scorekeeper';
const SECRET_KEY  = 'CHANGE-ME';   // must match DRIVE_KEY in the scorekeeper

function doPost(e) {
  try {
    const body = JSON.parse(e.postData.contents);
    if (body.key !== SECRET_KEY) return reply({ ok: false, error: 'bad key' });

    const match = body.match;
    if (!match || !Array.isArray(match.events) || match.events.length === 0) {
      return reply({ ok: false, error: 'no match data' });
    }

    // Only allow a plain .json file name.
    let name = String(body.filename || 'match.json').replace(/[^A-Za-z0-9._ -]/g, '-');
    if (!/\.json$/i.test(name)) name += '.json';

    const content = JSON.stringify(match, null, 1);
    const folder = getFolder();
    const existing = folder.getFilesByName(name);
    if (existing.hasNext()) {
      existing.next().setContent(content);          // re-send of the same match: overwrite
    } else {
      folder.createFile(name, content, 'application/json');
    }
    return reply({ ok: true, name: name, folder: FOLDER_NAME });
  } catch (err) {
    return reply({ ok: false, error: String(err) });
  }
}

// Visiting the URL in a browser just confirms it's alive.
function doGet() {
  return reply({ ok: true, service: 'scorekeeper-drive', folder: FOLDER_NAME });
}

function getFolder() {
  const found = DriveApp.getFoldersByName(FOLDER_NAME);
  return found.hasNext() ? found.next() : DriveApp.createFolder(FOLDER_NAME);
}

function reply(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
