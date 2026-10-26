import 'dart:io';

import 'package:flutter/material.dart';

import '../../api/innertube.dart' as yt;
import '../../api/spotify.dart';
import '../../models.dart';
import '../../services/library.dart';
import '../../services/playlist_import.dart';
import '../theme.dart';
import '../widgets/widgets.dart';
import 'collection_page.dart';

/// Brings a public playlist into Encore from its link: YouTube / YouTube
/// Music playlists as they are, Spotify playlists and albums by finding
/// each song on YouTube Music, with a look at the ones it isn't sure of.
class ImportPage extends StatefulWidget {
  const ImportPage({super.key, this.link});

  /// Starts importing this link straight away.
  final String? link;

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  final _controller = TextEditingController();

  /// Importing: what it's doing, or the error that stopped it.
  String? _status;
  String? _error;
  SpotifyImport? _spotify;
  var _matching = false;

  @override
  void initState() {
    super.initState();
    if (widget.link case final link?) {
      _controller.text = link;
      _import();
    }
  }

  @override
  void dispose() {
    _spotify?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final link = PlaylistLink.parse(_controller.text);
    if (link == null) {
      setState(
        () => _error =
            "That isn't a playlist link. Paste a link to a YouTube Music, "
            'YouTube or Spotify playlist.',
      );
      return;
    }
    setState(() {
      _status = 'Opening the playlist…';
      _error = null;
      _spotify = null;
    });
    try {
      switch (link) {
        case YouTubeLink(:final id):
          final list = await yt.collection('VL$id');
          if (list.tracks.isEmpty) throw 'This playlist has no songs.';
          final playlist = userLibrary.createPlaylist(
            list.title,
            tracks: list.tracks,
            source: 'YouTube Music',
          );
          _done(playlist);
        case SpotifyLink(:final kind, :final id):
          final list = await spotifyList(kind, id);
          if (list.songs.isEmpty) throw 'This playlist has no songs.';
          final import = SpotifyImport(list);
          if (!mounted) return;
          setState(() {
            _spotify = import;
            _matching = true;
          });
          await import.run();
          if (mounted) setState(() => _matching = false);
      }
    } catch (e) {
      // Back to the link, with what went wrong under it.
      if (!mounted) return;
      setState(() {
        _status = null;
        _spotify = null;
        _error = switch (e) {
          String message => message,
          HttpException(:final message) when message.contains('Spotify') =>
            message,
          _ =>
            "Couldn't open this playlist. Check the link, that the playlist "
                "is public, and that you're online.",
        };
      });
    }
  }

  void _done(Playlist playlist) {
    if (!mounted) return;
    showToast(
      context,
      'Imported ${songCount(playlist.tracks.length)} into "${playlist.name}"',
    );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => CollectionPage.playlist(playlist.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    final Widget body;
    if (_spotify case final import?) {
      body = _matching ? _Matching(import) : _Review(import, onSave: _done);
    } else if (_status case final status?) {
      body = Message(icon: Icons.downloading_rounded, text: status);
    } else {
      body = ListView(
        padding: EdgeInsets.fromLTRB(pad, 8, pad, 24),
        children: [
          Text(
            'Paste a link to a public playlist from YouTube Music, YouTube '
            'or Spotify. Its songs are copied into a new playlist here.',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: EncoreColors.textSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'https://open.spotify.com/playlist/…',
              prefixIcon: Icon(Icons.link_rounded),
            ),
            onSubmitted: (_) => _import(),
          ),
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, _) => FilledButton.icon(
                onPressed: _controller.text.trim().isEmpty ? null : _import,
                icon: const Icon(Icons.download_rounded),
                label: const Text('Import'),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'Private playlist? Make it public (or unlisted on YouTube), '
            'import it, then make it private again. Spotify shares only '
            'the first $spotifyLimit songs of a playlist this way.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: EncoreColors.textTertiary),
          ),
        ],
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Import playlist')),
      body: body,
    );
  }
}

class _Matching extends StatelessWidget {
  const _Matching(this.import);

  final SpotifyImport import;

  @override
  Widget build(BuildContext context) {
    final total = import.list.songs.length;
    return ValueListenableBuilder(
      valueListenable: import.matched,
      builder: (context, matched, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                import.list.name,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: 280,
                child: LinearProgressIndicator(
                  value: total == 0 ? null : matched / total,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Finding songs on YouTube Music… $matched of $total',
                style: const TextStyle(color: EncoreColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The matches, the unsure ones first, each changeable before saving.
class _Review extends StatefulWidget {
  const _Review(this.import, {required this.onSave});

  final SpotifyImport import;
  final void Function(Playlist) onSave;

  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  var _showSure = false;
  var _saved = false;

  Future<void> _change(BuildContext context, ImportMatch match) =>
      showActionMenu(context, [
        for (final t in match.candidates)
          MenuAction(
            t == match.chosen
                ? Icons.check_circle_rounded
                : Icons.music_note_rounded,
            '${t.title} — ${t.artist}',
            (_) => setState(() => match.chosen = t),
            detail: t.duration == null ? null : formatDuration(t.duration!),
          ),
        MenuAction(
          Icons.block_rounded,
          'Leave it out',
          (_) => setState(() => match.chosen = null),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final import = widget.import;
    final list = import.list;
    final pad = pagePadding(context);
    final unsure = import.matches.where((m) => !m.sure).toList();
    final sure = import.matches.where((m) => m.sure).toList();
    final chosen = import.matches.where((m) => m.chosen != null).length;
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(pad, 8, pad, 4),
                child: Text(list.name, style: text.headlineSmall),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: pad),
                child: Text(
                  unsure.isEmpty
                      ? 'All ${list.songs.length} songs found on YouTube Music.'
                      : '${sure.length} of ${list.songs.length} songs found. '
                            '${unsure.length} need a look: check the match '
                            'or tap to change it.',
                  style: const TextStyle(color: EncoreColors.textSecondary),
                ),
              ),
              if (list.total > list.songs.length)
                Padding(
                  padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
                  child: Text(
                    'Spotify shares only the first ${list.songs.length} of '
                    'its ${list.total} songs without signing in.',
                    style: const TextStyle(color: EncoreColors.accent),
                  ),
                ),
              if (unsure.isNotEmpty) ...[
                const SectionHeader('Need a look'),
                for (final m in unsure) _MatchRow(m, onTap: _change),
              ],
              if (sure.isNotEmpty) ...[
                SectionHeader(
                  'Found (${sure.length})',
                  // Folded away only below the ones that need a look.
                  action: unsure.isEmpty
                      ? null
                      : TextButton(
                          onPressed: () =>
                              setState(() => _showSure = !_showSure),
                          child: Text(_showSure ? 'Hide' : 'Show'),
                        ),
                ),
                if (_showSure || unsure.isEmpty)
                  for (final m in sure) _MatchRow(m, onTap: _change),
              ],
            ],
          ),
        ),
        const Divider(),
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 8, pad, 12),
          child: SafeArea(
            top: false,
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                // Once: a second tap mustn't make a second playlist.
                onPressed: chosen == 0 || _saved
                    ? null
                    : () {
                        setState(() => _saved = true);
                        widget.onSave(import.save());
                      },
                icon: const Icon(Icons.playlist_add_check_rounded),
                label: Text('Save playlist (${songCount(chosen)})'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow(this.match, {required this.onTap});

  final ImportMatch match;
  final Future<void> Function(BuildContext, ImportMatch) onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final chosen = match.chosen;
    final pad = pagePadding(context);
    final secondary = text.bodySmall?.copyWith(
      color: EncoreColors.textSecondary,
    );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: pad - 8),
      child: Builder(
        builder: (context) => InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: match.candidates.isEmpty ? null : () => onTap(context, match),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                chosen == null
                    ? Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: EncoreColors.surfaceHigh,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.block_rounded,
                          color: EncoreColors.textTertiary,
                        ),
                      )
                    : Artwork(chosen.artUrl, size: 48, radius: 6),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chosen?.title ?? match.song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall?.copyWith(fontSize: 15),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        chosen?.artist ??
                            (match.candidates.isEmpty
                                ? 'Not found on YouTube Music'
                                : 'Left out'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: secondary,
                      ),
                      if (!match.sure)
                        Text(
                          'Spotify: ${match.song.title} — ${match.song.artist}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(
                            color: EncoreColors.textTertiary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (match.candidates.isNotEmpty)
                  const Icon(
                    Icons.swap_horiz_rounded,
                    color: EncoreColors.textTertiary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
