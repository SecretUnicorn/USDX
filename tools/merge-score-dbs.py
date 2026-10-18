#!/usr/bin/env python3
"""Merge the score databases of several UltraStar Deluxe versions into one.

Every version keeps its own profile directory ("UltraStarDeluxe2026.8.1",
"UltraStarDeluxe2026.10.0+dev", ...), each with its own Ultrastar.db, so the
statistics and high scores of older versions stay invisible after an update.
This merges them into one database.

    python3 tools/merge-score-dbs.py                 # show what would happen
    python3 tools/merge-score-dbs.py --apply         # do it (backs up first)
    python3 tools/merge-score-dbs.py --target <db> --source <db> [...] --apply
    python3 tools/merge-score-dbs.py --self-test

Songs are matched by artist and title, scores are deduplicated on
artist/title/difficulty/player/score/date, so running it twice is harmless.
"""

import argparse
import io
import json
import os
import shutil
import sqlite3
import sys
import time
from glob import glob

# us_webs, us_webs_stats and us_users_info belong to the score upload feature
# and are empty in practice.
# shortcut: those three tables are not merged, revisit if anyone ever uses the
# web score upload.
SONG_COLUMNS = [
    'Artist', 'Title', 'TimesPlayed', 'Rating', 'VideoRatioAspect',
    'VideoWidth', 'VideoHeight', 'LyricPosition', 'LyricAlpha',
    'LyricSingFillColor', 'LyricActualFillColor', 'LyricNextFillColor',
    'LyricSingOutlineColor', 'LyricActualOutlineColor', 'LyricNextOutlineColor',
]


def find_databases():
    """The usual profile locations, newest modification first."""
    home = os.path.expanduser('~')
    patterns = [
        # the directory carried the version until 2026.10, "UltraStar Deluxe" since
        os.path.join(home, 'Library', 'Application Support', 'UltraStar*Deluxe*', 'Ultrastar.db'),
        os.path.join(home, '.ultrastardx*', 'Ultrastar.db'),
        os.path.join(home, '.local', 'share', 'ultrastardx*', 'Ultrastar.db'),
        os.path.join(os.environ.get('APPDATA', home), 'ultrastar*', 'Ultrastar.db'),
    ]
    found = []
    for pattern in patterns:
        found.extend(glob(pattern))
    return sorted(set(found), key=os.path.getmtime, reverse=True)


def state_path(target):
    return target + '.merged.json'


def load_state(target):
    """What was merged into this database before, per source and song."""
    try:
        with io.open(state_path(target), encoding='utf-8') as handle:
            return json.load(handle)
    except (IOError, ValueError):
        return {}


def score_columns(conn):
    """2026.10 added TrackCount and TrackMask so duets score per track."""
    names = [row[1] for row in conn.execute('PRAGMA table_info(us_scores)')]
    return [name for name in ('TrackCount', 'TrackMask') if name in names]


def clean(value):
    # versions up to 2026.4 stored the artist and title with the terminating
    # zero byte of the Pascal string, 2026.5 and later do not
    return value.replace('\0', '').strip()


def song_key(artist, title):
    return (clean(artist).lower(), clean(title).lower())


def merge(target_conn, source_path, report, state=None):
    source = sqlite3.connect('file:%s?mode=ro' % source_path, uri=True)
    if (state is None):
        state = {}
    # TimesPlayed is a sum, not a set of rows, so remember what this source
    # already contributed instead of adding it again on the next run
    before = state.get(source_path, {})
    now = {}
    try:
        cur = target_conn.cursor()

        # carry the track columns over when both sides have them, so a duet
        # score does not turn into a solo one
        extra = [name for name in score_columns(source)
                 if name in score_columns(target_conn)]
        extra_select = ''.join(', ' + name for name in extra)

        # so the game finds these rows again, and so both spellings of a song
        # end up on the same row below
        cur.execute("UPDATE us_songs SET Artist = replace(Artist, char(0), ''), "
                    "Title = replace(Title, char(0), '') "
                    'WHERE instr(Artist, char(0)) > 0 OR instr(Title, char(0)) > 0')
        cur.execute("UPDATE us_scores SET Player = replace(Player, char(0), '') "
                    'WHERE instr(Player, char(0)) > 0')

        songs = {}
        for row in cur.execute('SELECT ID, Artist, Title FROM us_songs'):
            songs[song_key(row[1], row[2])] = row[0]

        scores = set()
        for row in cur.execute(
                'SELECT s.Artist, s.Title, c.Difficulty, c.Player, c.Score, c.Date' +
                ''.join(', c.' + name for name in extra) +
                ' FROM us_scores c JOIN us_songs s ON s.ID = c.SongID'):
            scores.add(song_key(row[0], row[1]) +
                       (row[2], clean(row[3]), row[4], row[5]) + tuple(row[6:]))

        for row in source.execute('SELECT ID, %s FROM us_songs' % ', '.join(SONG_COLUMNS)):
            source_id, artist, title, times_played = row[0], row[1], row[2], row[3]
            key = song_key(artist, title)

            flat = '\t'.join(key)
            now[flat] = times_played
            delta = times_played - before.get(flat, 0)

            if key in songs:
                if (delta != 0):
                    cur.execute('UPDATE us_songs SET TimesPlayed = max(0, TimesPlayed + ?) '
                                'WHERE ID = ?', (delta, songs[key]))
                # the display settings of the target win, fill in only what it lacks
                for name, value in zip(SONG_COLUMNS[3:], row[4:]):
                    if value is not None:
                        cur.execute('UPDATE us_songs SET %s = ? WHERE ID = ? AND %s IS NULL'
                                    % (name, name), (value, songs[key]))
                if (delta != 0):
                    report['songs_updated'] += 1
            else:
                cur.execute('INSERT INTO us_songs (%s) VALUES (%s)'
                            % (', '.join(SONG_COLUMNS), ', '.join('?' * len(SONG_COLUMNS))),
                            (clean(artist), clean(title), max(0, delta)) + row[4:])
                songs[key] = cur.lastrowid
                report['songs_added'] += 1

            for score_row in source.execute(
                    'SELECT Difficulty, Player, Score, Date' + extra_select +
                    ' FROM us_scores WHERE SongID = ?', (source_id,)):
                entry = (score_row[0], clean(score_row[1])) + tuple(score_row[2:])
                if key + entry in scores:
                    report['scores_skipped'] += 1
                    continue

                cur.execute('INSERT INTO us_scores (SongID, Difficulty, Player, Score, Date%s) '
                            'VALUES (%s)' % (''.join(', ' + name for name in extra),
                                             ', '.join('?' * (5 + len(extra)))),
                            (songs[key], entry[0], entry[1]) + tuple(entry[2:]))
                scores.add(key + entry)
                report['scores_added'] += 1

        # "statistics since" should cover the oldest data that is now in there
        reset = source.execute('SELECT ResetTime FROM us_statistics_info').fetchone()
        if reset and reset[0]:
            cur.execute('UPDATE us_statistics_info SET ResetTime = ? '
                        'WHERE ResetTime IS NULL OR ResetTime > ?', (reset[0], reset[0]))
        state[source_path] = now
    finally:
        source.close()


def totals(path):
    conn = sqlite3.connect('file:%s?mode=ro' % path, uri=True)
    try:
        return conn.execute('SELECT (SELECT COUNT(*) FROM us_songs), '
                            '(SELECT COUNT(*) FROM us_scores)').fetchone()
    finally:
        conn.close()


def run(target, sources, apply_changes):
    print('target : %s  (%d songs, %d scores)' % ((target,) + totals(target)))
    for source in sources:
        print('source : %s  (%d songs, %d scores)' % ((source,) + totals(source)))
    print()

    if apply_changes:
        backup = '%s.bak-%s' % (target, time.strftime('%Y%m%d-%H%M%S'))
        shutil.copy2(target, backup)
        print('backup : %s' % backup)

    state = load_state(target)
    conn = sqlite3.connect(target)
    try:
        for source in sources:
            report = dict(songs_added=0, songs_updated=0, scores_added=0, scores_skipped=0)
            merge(conn, source, report, state)
            print('%-52s +%d scores (%d already there), +%d songs, %d songs updated'
                  % (os.path.basename(os.path.dirname(source)), report['scores_added'],
                     report['scores_skipped'], report['songs_added'], report['songs_updated']))

        after = conn.execute('SELECT (SELECT COUNT(*) FROM us_songs), '
                             '(SELECT COUNT(*) FROM us_scores)').fetchone()
        if apply_changes:
            conn.commit()
            with io.open(state_path(target), 'w', encoding='utf-8') as handle:
                handle.write(json.dumps(state, ensure_ascii=False, indent=1))
        else:
            conn.rollback()
    finally:
        conn.close()

    print()
    print('result : %d songs, %d scores%s' % (after[0], after[1],
                                              '' if apply_changes else '  (nothing written, '
                                              'pass --apply to keep it)'))
    return 0


def self_test():
    import tempfile

    def build(path, songs):
        conn = sqlite3.connect(path)
        conn.execute('CREATE TABLE [us_songs] ([ID] INTEGER PRIMARY KEY, [Artist] TEXT NOT NULL, '
                     '[Title] TEXT NOT NULL, [TimesPlayed] INTEGER NOT NULL, [Rating] INTEGER NULL, '
                     '[VideoRatioAspect] INTEGER NULL, [VideoWidth] INTEGER NULL, '
                     '[VideoHeight] INTEGER NULL, [LyricPosition] INTEGER NULL, '
                     '[LyricAlpha] INTEGER NULL, [LyricSingFillColor] TEXT NULL, '
                     '[LyricActualFillColor] TEXT NULL, [LyricNextFillColor] TEXT NULL, '
                     '[LyricSingOutlineColor] TEXT NULL, [LyricActualOutlineColor] TEXT NULL, '
                     '[LyricNextOutlineColor] TEXT NULL)')
        conn.execute('CREATE TABLE [us_scores] ([SongID] INTEGER NOT NULL, '
                     '[Difficulty] INTEGER NOT NULL, [Player] TEXT NOT NULL, '
                     '[Score] INTEGER NOT NULL, [Date] INTEGER NULL)')
        conn.execute('CREATE TABLE [us_statistics_info] ([ResetTime] INTEGER)')
        conn.execute('INSERT INTO us_statistics_info VALUES (?)', (songs.pop('reset'),))
        for song_id, (artist, title, played, score_rows) in enumerate(songs['songs'], start=1):
            conn.execute('INSERT INTO us_songs (ID, Artist, Title, TimesPlayed) VALUES (?,?,?,?)',
                         (song_id, artist, title, played))
            for row in score_rows:
                conn.execute('INSERT INTO us_scores VALUES (?,?,?,?,?)', (song_id,) + row)
        conn.commit()
        conn.close()

    tmp = tempfile.mkdtemp()
    target = os.path.join(tmp, 'target.db')
    source = os.path.join(tmp, 'source.db')
    # the same song in both, plus one score that exists in both
    build(target, {'reset': 200, 'songs': [('ABBA', 'Mamma Mia', 2, [(0, 'Nicklas', 8000, 50)])]})
    build(source, {'reset': 100, 'songs': [
        ('abba\0', 'mamma mia\0', 3, [(0, 'Nicklas\0', 8000, 50), (1, 'Guest', 7000, 60)]),
        ('Queen', 'Bohemian Rhapsody', 1, [(0, 'Nicklas', 9000, 70)])]})

    conn = sqlite3.connect(target)
    state = {}
    report = dict(songs_added=0, songs_updated=0, scores_added=0, scores_skipped=0)
    merge(conn, source, report, state)
    conn.commit()

    # a second run must change nothing
    again = dict(songs_added=0, songs_updated=0, scores_added=0, scores_skipped=0)
    merge(conn, source, again, state)
    conn.commit()
    assert again == dict(songs_added=0, songs_updated=0, scores_added=0, scores_skipped=3), again

    songs, scores = conn.execute('SELECT (SELECT COUNT(*) FROM us_songs), '
                                 '(SELECT COUNT(*) FROM us_scores)').fetchone()
    played = conn.execute("SELECT TimesPlayed FROM us_songs WHERE Artist = 'ABBA'").fetchone()[0]
    reset = conn.execute('SELECT ResetTime FROM us_statistics_info').fetchone()[0]
    stored = conn.execute('SELECT COUNT(*) FROM us_songs WHERE instr(Artist, char(0)) > 0 '
                          'OR instr(Title, char(0)) > 0').fetchone()[0]
    stored += conn.execute('SELECT COUNT(*) FROM us_scores '
                           'WHERE instr(Player, char(0)) > 0').fetchone()[0]
    conn.close()
    shutil.rmtree(tmp)

    assert songs == 2, songs                       # ABBA matched despite case and zero byte
    assert scores == 3, scores                     # the duplicate was not copied
    assert played == 5, played                     # 2 + 3
    assert reset == 100, reset                     # the older start wins
    assert stored == 0, stored                     # nothing written with a zero byte
    assert report == dict(songs_added=1, songs_updated=1, scores_added=2, scores_skipped=1), report
    print('self test passed')
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--target', help='database to merge into (default: the newest one found)')
    parser.add_argument('--source', action='append', default=[],
                        help='database to merge from, repeatable (default: all others found)')
    parser.add_argument('--apply', action='store_true', help='write the changes')
    parser.add_argument('--self-test', action='store_true', help='check the merge logic and exit')
    args = parser.parse_args()

    if args.self_test:
        return self_test()

    found = find_databases()
    target = args.target or (found[0] if found else None)
    if not target:
        print('No Ultrastar.db found, pass --target.', file=sys.stderr)
        return 1

    sources = args.source or [db for db in found if os.path.abspath(db) != os.path.abspath(target)]
    if not sources:
        print('Nothing to merge into %s.' % target, file=sys.stderr)
        return 1

    return run(target, sources, args.apply)


if __name__ == '__main__':
    sys.exit(main())
