// Runs as a WKUserScript in the .defaultClient content world (page JS is off).
// Wire shape (frozen): Marked.render(html, changedLine) resolves exactly
//   {ok: boolean, errors: string[]}, each error "<hook name>: <message>".
//   Success = {ok: true, errors: []}. It never rejects.
window.Marked = { ping: () => "pong", token: crypto.randomUUID() };
