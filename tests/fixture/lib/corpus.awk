# corpus.awk: write the bulk text of the fixture guidelines corpus, deterministically.
#
# Usage: awk -v root=<dir> -f corpus.awk
# The directories under root must exist first (build.sh creates them). Writes
# <root>/<dir>/<dir>-<n>.md for each directory below, about 1 MB in all.
#
# The text is lowercase filler from a fixed word list and a fixed integer sequence, so
# every awk writes the same bytes and the text holds no rule keywords. The rule files
# are written separately by build.sh.
BEGIN {
	nd = split("style testing security operations data reviews", dirs, " ")
	nw = split("the a change file review test script record output input value " \
		"branch commit ticket owner team build release config module helper path " \
		"line column row field export import note guide example case check result " \
		"error message name reader writer page section list table step order " \
		"reason detail version default option flag setting user account report " \
		"log format tool", words, " ")
	s = 12345
	for (d = 1; d <= nd; d++) {
		for (f = 1; f <= 9; f++) {
			path = root "/" dirs[d] "/" dirs[d] "-" f ".md"
			printf "# %s notes %d\n", dirs[d], f > path
			for (p = 1; p <= 44; p++) {
				printf "\n## topic %d\n\n", p > path
				for (l = 1; l <= 6; l++) {
					line = ""
					for (w = 1; w <= 12; w++) {
						s = (s * 69069 + 1) % 4294967296
						word = words[int(s / 65536) % nw + 1]
						line = (w == 1) ? word : line " " word
					}
					print line "." > path
				}
			}
			close(path)
		}
	}
}
