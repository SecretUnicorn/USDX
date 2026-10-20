#!/usr/bin/env python3
"""Shuffle the UltraStar Deluxe song request queue.

    python3 tools/shuffle-web-queue.py                      # show the new order
    python3 tools/shuffle-web-queue.py --apply
    python3 tools/shuffle-web-queue.py --apply --host 192.168.1.20 --port 8080
    python3 tools/shuffle-web-queue.py --apply --keep-first # leave the next song alone

The game offers no shuffle endpoint, but /api/queue/move swaps two entries and
takes any offset, so a Fisher-Yates shuffle is one request per swap. Nothing
else is touched: no entry is added, removed or re-queued, and the game is not
restarted.
"""

import argparse
import json
import random
import sys
import urllib.error
import urllib.parse
import urllib.request


def api(base, path, data=None, timeout=5):
    url = base + path
    if data is None:
        request = urllib.request.Request(url)
    else:
        request = urllib.request.Request(
            url, data=urllib.parse.urlencode(data).encode(),
            headers={'Content-Type': 'application/x-www-form-urlencoded'})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode('utf-8'))


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=8080)
    parser.add_argument('--apply', action='store_true', help='send the swaps')
    parser.add_argument('--keep-first', action='store_true',
                        help='do not move the entry at the top of the queue')
    parser.add_argument('--seed', type=int, help='reproducible shuffle')
    args = parser.parse_args()

    base = 'http://%s:%d' % (args.host, args.port)
    try:
        queue = api(base, '/api/queue')
    except (urllib.error.URLError, OSError) as error:
        print('Cannot reach %s: %s' % (base, error), file=sys.stderr)
        return 1

    entries = queue['entries']
    if (len(entries) < 2):
        print('Nothing to shuffle, the queue has %d entries.' % len(entries))
        return 0

    rng = random.Random(args.seed)
    order = list(entries)
    first = 1 if args.keep_first else 0
    swaps = []

    # Fisher-Yates, recorded as the swaps the move endpoint understands
    for i in range(len(order) - 1, first, -1):
        j = rng.randrange(first, i + 1)
        if (i == j):
            continue
        swaps.append((order[i]['entry'], j - i))
        order[i], order[j] = order[j], order[i]

    for position, entry in enumerate(order, start=1):
        print('%2d. %s - %s%s' % (position, entry['artist'], entry['title'],
                                  '  (%s)' % entry['singer'] if entry['singer'] else ''))
    print()

    if not args.apply:
        print('%d swaps, nothing sent. Pass --apply to shuffle the real queue.' % len(swaps))
        return 0

    for entry_id, offset in swaps:
        try:
            result = api(base, '/api/queue/move', dict(entry=entry_id, offset=offset))
        except (urllib.error.URLError, OSError) as error:
            print('Swap failed, the queue is half shuffled: %s' % error, file=sys.stderr)
            return 1

        # someone removed an entry or sang it while we were shuffling
        if not result.get('ok'):
            print('The queue changed while shuffling, run it again.', file=sys.stderr)
            return 1

    print('Shuffled %d entries with %d swaps.' % (len(order), len(swaps)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
