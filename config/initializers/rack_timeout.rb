# frozen_string_literal: true

# Last-resort backstop that reclaims a Puma thread (and the DB connection it holds)
# if a conversation turn wedges. This is NOT a UX timeout — it is set well above any
# legitimate turn so it only ever fires on a genuinely stuck thread.
#
# Scope: this wraps ONE web request = ONE conversation turn (a HASS POST to
# /api/v1/conversation). It covers only the SYNCHRONOUS orchestrator pipeline —
# Setup, PromptBuilder, the brain LLM call, ResponseSynthesizer, Finalizer. All the
# async work (EnvironmentDirectorJob's HASS agent call, camera, summarizers, shows)
# runs in SolidQueue and is NOT covered by this timer.
#
# Sizing: the dominant cost is the brain LLM call. LlmService can chain calls on a
# bad-luck turn — primary (openrouter request_timeout 45s) + fallback-on-timeout
# (up to 2 x 45s) + up to 2 heal attempts + a secondary retry — so a slow-but-VALID
# turn can run well over a minute. 180s sits comfortably above that chain: it exists
# only to reclaim a genuinely wedged thread, never to cut off a turn that would have
# returned. The HASS voice client has given up long before this fires anyway, and on
# a single-user 5-thread cube holding one wedged thread a little longer is harmless —
# so err high. Bump it further if a legit turn ever gets killed.
#
# On timeout rack-timeout raises Rack::Timeout::RequestTimeoutError inside the request;
# ConversationController's rescue turns it into the standard safe HASS error response.
#
# Inserted manually (gem is required as rack/timeout/base, so it does NOT auto-insert
# its 15s default). Placed outermost so the timer covers the whole middleware stack.
Rails.application.config.middleware.insert 0, Rack::Timeout,
  service_timeout: 180,   # seconds of synchronous turn work before the thread is reclaimed
  wait_timeout:    false  # single-user cube: don't 503 on queue wait
