'use strict';

// HTTP chunks are not message boundaries; retain both split UTF-8 and a final unterminated line.
async function* lines(body) {
  const decoder = new TextDecoder();
  let buffer = '';
  for await (const chunk of body) {
    buffer += decoder.decode(chunk, {
      stream: true
    });
    let nl;
    while ((nl = buffer.indexOf('\n')) >= 0) {
      yield buffer.slice(0, nl).trim();
      buffer = buffer.slice(nl + 1);
    }
  }
  buffer += decoder.decode();
  if (buffer.trim()) yield buffer.trim();
}
module.exports = {
  lines
};
