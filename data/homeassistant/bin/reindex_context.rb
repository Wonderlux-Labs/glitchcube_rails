#!/usr/bin/env ruby
# Refresh the `_line ~N_` markers in AUTOMATIONS_AND_SCRIPTS.md from the current
# automations.yaml / scripts.yaml. Run after you edit in the HA UI and scp the
# files back into the repo (line numbers drift on every UI re-save).
#
#   ruby bin/reindex_context.rb        # from data/homeassistant/
#
# Also reports drift: README entries whose id/slug no longer exists (deleted in
# the UI) and YAML items with no README entry (created in the UI — go document them).
require "yaml"

HA = File.expand_path(File.join(__dir__, ".."))
Dir.chdir(HA)

README = "AUTOMATIONS_AND_SCRIPTS.md"

def line_index(file, pattern_for)
  idx = {}
  File.readlines(file).each_with_index do |l, i|
    key = pattern_for.call(l)
    idx[key] = i + 1 if key
  end
  idx
end

# id  -> line in automations.yaml (matches "- id: foo" / "- id: 'foo'")
auto_lines = line_index("automations.yaml", ->(l) {
  l =~ /^-\s+id:\s*['"]?([^'"\s]+)['"]?\s*$/ ? $1 : nil
})
# slug -> line in scripts.yaml (top-level mapping key "foo:")
scr_lines = line_index("scripts.yaml", ->(l) {
  l =~ /^([a-zA-Z0-9_]+):\s*$/ ? $1 : nil
})
all_lines = auto_lines.merge(scr_lines)

seen = {}
updated = 0
lines = File.readlines(README).map do |line|
  # item line: - **`key`** ... — _line ~N_
  if line =~ /^(-\s+\*\*`)([^`]+)(`\*\*.*?—\s*_line ~)(\d+)(_.*)$/m
    key = $2
    seen[key] = true
    if (n = all_lines[key])
      updated += 1 if $4 != n.to_s
      next "#{$1}#{key}#{$3}#{n}#{$5}"
    else
      warn "ORPHAN in README (no such id/slug in YAML anymore): #{key}"
    end
  end
  line
end

File.write(README, lines.join)

undocumented = all_lines.keys.reject { |k| seen[k] }
warn "UNDOCUMENTED (in YAML, missing from README): #{undocumented.join(', ')}" unless undocumented.empty?

puts "reindexed #{README}: #{all_lines.size} items, #{updated} line markers changed"
