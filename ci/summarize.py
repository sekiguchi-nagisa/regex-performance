#!/usr/bin/env python3
"""Print a Markdown summary of a results.csv written by regex_perf.

The table lists the average and the slowest pattern of every measured engine, so the CI job
summary shows at a glance that every engine really ran.

Usage: ci/summarize.py <results.csv>
"""

import csv
import sys

# regex_perf reports a timeout as this many milliseconds (see src/main.c)
TIMEOUT_MS = 999999


def main(path):
    # the CSV is separated by ';' and ends every line with a trailing separator, so DictReader
    # sees an extra empty field; it is ignored here.
    with open(path, newline="") as f:
        rows = list(csv.DictReader(f, delimiter=";"))
    if not rows:
        print("no benchmark results", file=sys.stderr)
        return 1

    engines = [column[:-5] for column in rows[0] if column.endswith(" [ms]")]
    print("### Average time per engine (ms)")
    print()
    print("| engine | average | slowest pattern |")
    print("|--------|---------|-----------------|")
    for engine in engines:
        column = f"{engine} [ms]"
        times = [float(row[column]) for row in rows if row[column].strip()]
        measured = [t for t in times if 0 < t < TIMEOUT_MS]
        if measured:
            print(f"| {engine} | {sum(measured) / len(measured):.1f} | {max(measured):.1f} |")
        else:
            print(f"| {engine} | n/a | n/a |")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
