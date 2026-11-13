const assert = require("node:assert/strict");
const { test } = require("node:test");
const { onExecutePostLogin } = require("./require-verified-email.js");

for (const { name, connection, verified, denied } of [
  { name: "refuses an unverified shared account", connection: "arconis", verified: false, denied: true },
  { name: "allows a verified shared account", connection: "arconis", verified: true, denied: false },
  { name: "leaves unrelated connections alone", connection: "unrelated", verified: false, denied: false },
]) {
  test(name, async () => {
    const messages = [];
    await onExecutePostLogin(
      { connection: { name: connection }, user: { email_verified: verified } },
      { access: { deny: (message) => messages.push(message) } }
    );
    assert.equal(messages.length, denied ? 1 : 0);
    if (denied) assert.match(messages[0], /Verify your Ahara account/);
  });
}
