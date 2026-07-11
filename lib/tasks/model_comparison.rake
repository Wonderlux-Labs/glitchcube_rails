# Compare the cost + speed of brain models by driving them through the real
# conversation brain path (ConversationOrchestrator::LlmIntention →
# LlmService.call_with_structured_output with the live NarrativeResponseSchema).
# Each call records the same tokens/cost/provider/latency metrics we persist on
# ConversationLog, so this is an apples-to-apples read of what a turn actually costs.
#
#   MODELS="deepseek/deepseek-v4-flash:nitro,google/gemini-flash-3-preview" \
#   ROUNDS=3 bin/rails models:compare
#
# Env:
#   MODELS  (required) comma-separated OpenRouter model ids. Append :nitro to route
#           to the fastest provider (kills the slow-provider tail — worth testing).
#   ROUNDS  (default 3) calls per model.
#   PROMPT  (optional) the visitor line. SYSTEM (optional) the system prompt.
#
# Note: this exercises ONLY the brain call (the expensive, latency-critical hop),
# not the async action agent or TTS — latency here ≈ time-to-speech.
namespace :models do
  desc "Compare cost/speed of brain models. MODELS=a,b[,c] ROUNDS=3 bin/rails models:compare"
  task compare: :environment do
    models = ENV.fetch("MODELS", "").split(",").map(&:strip).reject(&:empty?)
    abort "Set MODELS=model1,model2,... (comma-separated OpenRouter ids)" if models.empty?
    rounds = (ENV["ROUNDS"] || "3").to_i
    user   = ENV["PROMPT"] || "A restless stranger walks up and asks: where should I even go tonight, what's worth doing out here?"
    system = ENV["SYSTEM"] || "You are a persona of the GlitchCube, an interactive art-installation cube at a festival. Stay in character, speak aloud, keep it short."

    med = ->(a) { a = a.compact.sort; a.empty? ? 0 : a[a.size / 2] }
    p95 = ->(a) { a = a.compact.sort; a.empty? ? 0 : a[[ (a.size * 0.95).ceil - 1, a.size - 1 ].min.clamp(0, a.size - 1)] }

    rows = models.map do |m|
      puts "\n▶ #{m}"
      samples = []
      rounds.times do |i|
        res = ConversationOrchestrator::LlmIntention.call(
          prompt_data: { system_prompt: system, messages: [ { role: "user", content: user } ] },
          user_message: user,
          model: m
        )
        u = res.data[:usage]
        if u
          samples << u
          puts format("  r%-2d %6dms  $%-10.6f %5d/%-4d tok  %6.1f tps  %s",
                      i + 1, u["latency_ms"].to_i, u["cost"].to_f, u["prompt_tokens"].to_i,
                      u["completion_tokens"].to_i, u["tokens_per_second"].to_f, u["provider"])
        else
          # LlmIntention swallows brain errors and returns a fallback narrative with
          # usage:nil — so a nil here means the model errored/timed out on that round.
          puts "  r#{i + 1}  FAILED (model errored — see log; counts against reliability)"
        end
      end
      { model: m, samples: samples, fails: rounds - samples.size }
    end

    puts "\n" + "=" * 104
    printf "%-34s %5s %8s %8s %8s %11s %9s %6s  %s\n",
           "MODEL", "ok", "med_ms", "p95_ms", "max_ms", "med_$/turn", "$/1k", "tps", "provider(s)"
    puts "-" * 104
    rows.each do |r|
      s = r[:samples]
      if s.empty?
        printf "%-34s %5s  ALL FAILED\n", r[:model], "0/#{r[:fails]}"
        next
      end
      lat  = s.map { |x| x["latency_ms"] }
      cost = s.map { |x| x["cost"].to_f }
      printf "%-34s %5s %7dms %7dms %7dms $%.6f $%7.2f %6.0f  %s\n",
             r[:model], "#{s.size}/#{s.size + r[:fails]}",
             med.(lat), p95.(lat), lat.max, med.(cost), med.(cost) * 1000,
             med.(s.map { |x| x["tokens_per_second"] }),
             s.map { |x| x["provider"] }.compact.uniq.join(",")
    end
    puts "=" * 104
    puts "med_$/turn = median cost per brain call · $/1k = projected per 1000 turns · latency ≈ time-to-speech"
    puts "Tip: a wide provider spread or a bad p95/max on a non-:nitro model is exactly what :nitro fixes."
  end
end
