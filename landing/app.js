/* ============================================================
   Togi waitlist — stores signups (name + email) in your Supabase
   `waitlist` table. The anon key in config.js is browser-safe
   (RLS allows insert-only): visitors can join but cannot read the list.
   ============================================================ */
(function () {
  "use strict";

  var form = document.getElementById("waitlist-form");
  var first = document.getElementById("first");
  var last = document.getElementById("last");
  var email = document.getElementById("email");
  var button = document.getElementById("submit");
  var message = document.getElementById("message");

  var cfg = window.TOGI_CONFIG || {};
  var supabase = null;
  if (cfg.SUPABASE_URL && cfg.SUPABASE_ANON_KEY && window.supabase) {
    supabase = window.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY);
  }

  function setMessage(text, kind) {
    message.textContent = text;
    message.className = "message" + (kind ? " " + kind : "");
  }
  function setLoading(on) {
    button.disabled = on;
    button.classList.toggle("loading", on);
    first.disabled = last.disabled = email.disabled = on;
  }
  function validEmail(v) { return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v); }

  form.addEventListener("submit", function (e) {
    e.preventDefault();
    var fn = (first.value || "").trim();
    var ln = (last.value || "").trim();
    var em = (email.value || "").trim().toLowerCase();

    if (!fn || !ln) { setMessage("Please enter your first and last name.", "err"); (fn ? last : first).focus(); return; }
    if (!validEmail(em)) { setMessage("Please enter a valid email address.", "err"); email.focus(); return; }

    if (!supabase) {
      setMessage("Thanks! Waitlist storage isn’t connected yet — try again soon.", "err");
      return;
    }

    setLoading(true);
    setMessage("", "");

    supabase
      .from("waitlist")
      .insert({ first_name: fn, last_name: ln, email: em, source: "heytogi.com" })
      .then(function (res) {
        setLoading(false);
        var error = res.error;
        if (!error) {
          form.reset();
          setMessage("You’re on the list — thank you. We’ll be in touch.", "ok");
          return;
        }
        if (error.code === "23505" || /duplicate|unique/i.test(error.message || "")) {
          form.reset();
          setMessage("You’re already on the list — thank you.", "ok");
          return;
        }
        console.error("waitlist insert failed:", error);
        setMessage("Hmm, something went wrong. Please try again.", "err");
      })
      .catch(function (err) {
        setLoading(false);
        console.error("waitlist insert threw:", err);
        setMessage("Hmm, something went wrong. Please try again.", "err");
      });
  });
})();
