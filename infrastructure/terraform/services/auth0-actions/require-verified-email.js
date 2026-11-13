/** The shared database keeps its historical internal name; unrelated connections stay untouched. */
exports.onExecutePostLogin = async (event, api) => {
  if (event.connection.name !== "arconis") return;
  if (!event.user.email_verified) {
    api.access.deny("Verify your Ahara account from the email we sent, then sign in again.");
  }
};
