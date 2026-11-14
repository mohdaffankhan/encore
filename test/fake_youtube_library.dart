import 'fake_youtube.dart';

/// A song as the fake account knows it.
class FakeSong {
  const FakeSong(this.id, [this.title = '']);

  final String id;
  final String title;
}

class FakePlaylist {
  FakePlaylist(this.id, this.title, List<String> songs, {this.owned = true})
    : entries = [for (final s in songs) FakeEntry(s)];

  final String id;
  String title;
  final bool owned;
  final List<FakeEntry> entries;

  List<String> get songs => [for (final e in entries) e.videoId];
}

var _nextEntry = 0;

class FakeEntry {
  FakeEntry(this.videoId) : setId = 'E${_nextEntry++}';

  final String videoId;
  final String setId;
}

/// A signed-in account's YouTube Music library, served by [FakeYouTube] in
/// the shapes YouTube Music uses (taken from real replies): Liked Music,
/// the account's playlists (with each entry's setVideoId), saved albums,
/// followed artists, and the requests that change them.
class FakeLibrary {
  FakeLibrary(this.youtube) {
    _install();
  }

  final FakeYouTube youtube;

  /// Newest first.
  final liked = <String>[];
  final playlists = <String, FakePlaylist>{};

  /// Saved albums (`MPRE…` page ids) and others' playlists (`VL…`).
  final savedAlbums = <String>[];
  final followed = <String>[];

  /// Each album's playlist (what saving it saves).
  String albumPlaylist(String browseId) => 'OLAK5uy_$browseId';

  /// Each artist's channel (what following subscribes to).
  String channelOf(String pageId) => pageId;

  var _created = 0;

  /// Songs a playlist can be made with in one request (a guess: YouTube's
  /// own limit isn't known; Encore sends 50).
  var createLimit = 50;

  /// The account's writes, in order, as `kind id…`.
  final writes = <String>[];

  void _install() {
    final h = youtube.handlers;
    h['browse'] = (r, signed) {
      final id = r.body['browseId'] as String?;
      if (!signed) return {};
      if (r.body['continuation'] case final String token) {
        return continuation(token);
      }
      if (r.query['ctoken'] case final String token) return continuation(token);
      if (id == null) return {};
      if (id == 'VLLM') return _playlistPage('LM', 'Liked Music', liked, owned: false, auto: true);
      if (id == 'FEmusic_liked_playlists') return _grid(_libraryCards());
      if (id == 'FEmusic_liked_albums') {
        return _grid([for (final a in savedAlbums) _card(a, 'Album $a', 'MUSIC_PAGE_TYPE_ALBUM')]);
      }
      if (id == 'FEmusic_library_corpus_artists') {
        return {
          'contents': [
            for (final a in followed) _artistRow('MPLA$a', 'Artist $a'),
          ],
        };
      }
      if (id.startsWith('VL')) {
        final p = playlists[id.substring(2)];
        if (p == null) return 404;
        return _playlistPage(p.id, p.title, p.songs, owned: p.owned, entries: p.entries);
      }
      if (id.startsWith('MPRE')) {
        return {
          'contents': [
            _bookmark(albumPlaylist(id), savedAlbums.contains(id)),
          ],
        };
      }
      if (id.startsWith('UC')) {
        return {
          'header': {
            'subscribeButtonRenderer': {
              'channelId': channelOf(id),
              'subscribed': followed.contains(channelOf(id)),
            },
          },
        };
      }
      return {};
    };
    h['like/like'] = (r, s) => _rate(r, true);
    h['like/removelike'] = (r, s) => _rate(r, false);
    h['playlist/create'] = (r, s) {
      if ((r.body['videoIds'] as List? ?? []).length > createLimit) return 400;
      final id = 'PLnew${_created++}';
      playlists[id] = FakePlaylist(
        id,
        r.body['title'] as String,
        [for (final v in r.body['videoIds'] as List? ?? []) v as String],
      );
      writes.add('create $id ${r.body['title']}');
      return {'playlistId': id};
    };
    h['playlist/delete'] = (r, s) {
      final id = r.body['playlistId'] as String;
      writes.add('delete $id');
      return playlists.remove(id) == null ? 404 : {};
    };
    h['browse/edit_playlist'] = (r, s) {
      final p = playlists[r.body['playlistId']];
      if (p == null || !p.owned) return 400;
      for (final a in (r.body['actions'] as List).cast<Map>()) {
        switch (a['action']) {
          case 'ACTION_ADD_VIDEO':
            final v = a['addedVideoId'] as String;
            if (!p.songs.contains(v)) p.entries.add(FakeEntry(v));
            writes.add('add ${p.id} $v');
          case 'ACTION_REMOVE_VIDEO':
            p.entries.removeWhere((e) => e.setId == a['setVideoId']);
            writes.add('remove ${p.id} ${a['removedVideoId']}');
          case 'ACTION_SET_PLAYLIST_NAME':
            p.title = a['playlistName'] as String;
            writes.add('rename ${p.id} ${p.title}');
          case 'ACTION_MOVE_VIDEO_BEFORE':
            final moved = p.entries.firstWhere((e) => e.setId == a['setVideoId']);
            p.entries.remove(moved);
            final before = a['movedSetVideoIdSuccessor'];
            final at = before == null
                ? p.entries.length
                : p.entries.indexWhere((e) => e.setId == before);
            p.entries.insert(at, moved);
            writes.add('move ${p.id} ${moved.videoId}');
        }
      }
      return {'status': 'STATUS_SUCCEEDED'};
    };
    h['subscription/subscribe'] = (r, s) {
      for (final c in r.body['channelIds'] as List) {
        if (!followed.contains(c)) followed.insert(0, c as String);
        writes.add('follow $c');
      }
      return {};
    };
    h['subscription/unsubscribe'] = (r, s) {
      for (final c in r.body['channelIds'] as List) {
        followed.remove(c);
        writes.add('unfollow $c');
      }
      return {};
    };
  }

  Object _rate(FakeRequest r, bool like) {
    final target = r.body['target'] as Map;
    if (target['videoId'] case final String v) {
      liked.remove(v);
      if (like) liked.insert(0, v);
      writes.add('${like ? 'like' : 'unlike'} $v');
      return {};
    }
    final list = target['playlistId'] as String;
    writes.add('${like ? 'save' : 'unsave'} $list');
    if (list.startsWith('OLAK5uy_')) {
      final album = list.substring(8);
      savedAlbums.remove(album);
      if (like) savedAlbums.insert(0, album);
    } else if (like) {
      playlists[list] ??= FakePlaylist(list, 'Saved $list', ['x'], owned: false);
    } else {
      playlists.remove(list);
    }
    return {};
  }

  List<Map<String, Object>> _libraryCards() => [
    // As the real page: "New playlist" (no link), Liked Music, Episodes.
    {
      'musicTwoRowItemRenderer': {
        'title': _runs('New playlist'),
        'navigationEndpoint': {'createPlaylistEndpoint': {}},
      },
    },
    _card('VLLM', 'Liked Music', 'MUSIC_PAGE_TYPE_PLAYLIST'),
    for (final p in playlists.values)
      _card('VL${p.id}', p.title, 'MUSIC_PAGE_TYPE_PLAYLIST'),
    _card('VLSE', 'Episodes for Later', 'MUSIC_PAGE_TYPE_PLAYLIST'),
  ];

  static Map<String, Object> _runs(String text) => {
    'runs': [
      {'text': text},
    ],
  };

  static Map<String, Object> _card(String id, String title, String type) => {
    'musicTwoRowItemRenderer': {
      'title': _runs(title),
      'subtitle': _runs('Playlist'),
      'navigationEndpoint': {
        'browseEndpoint': {
          'browseId': id,
          'browseEndpointContextSupportedConfigs': {
            'browseEndpointContextMusicConfig': {'pageType': type},
          },
        },
      },
    },
  };

  static Map<String, Object> _grid(List<Map<String, Object>> items) => {
    'contents': {
      'gridRenderer': {'items': items},
    },
  };

  static Map<String, Object> _artistRow(String id, String name) => {
    'musicResponsiveListItemRenderer': {
      'flexColumns': [
        {
          'musicResponsiveListItemFlexColumnRenderer': {'text': _runs(name)},
        },
      ],
      'navigationEndpoint': {
        'browseEndpoint': {
          'browseId': id,
          'browseEndpointContextSupportedConfigs': {
            'browseEndpointContextMusicConfig': {
              'pageType': 'MUSIC_PAGE_TYPE_ARTIST',
            },
          },
        },
      },
    },
  };

  static Map<String, Object> _bookmark(String playlistId, bool saved) => {
    'toggleButtonRenderer': {
      'isToggled': saved,
      'defaultIcon': {'iconType': 'BOOKMARK_BORDER'},
      'defaultServiceEndpoint': {
        'likeEndpoint': {
          'target': {'playlistId': playlistId},
        },
      },
    },
  };

  Map<String, Object> _playlistPage(
    String id,
    String title,
    List<String> songs, {
    required bool owned,
    bool auto = false,
    List<FakeEntry>? entries,
  }) {
    final header = {
      'musicResponsiveHeaderRenderer': {'title': _runs(title)},
    };
    final rows = [
      for (var i = 0; i < songs.length; i++)
        _row(songs[i], entries?[i].setId),
    ];
    // As the real page: songs in pages of [pageSize] (a "load more" item
    // at the end), and for the account's own playlists a suggestions shelf
    // below, loaded by the section list's own continuation.
    final first = rows.take(pageSize).toList();
    if (rows.length > pageSize) first.add(_more(id, pageSize));
    return {
      'header': owned
          ? {
              'musicEditablePlaylistDetailHeaderRenderer': {'header': header},
            }
          : header,
      if (!owned && !auto) 'bookmark': _bookmark(id, true),
      'contents': {
        'twoColumnBrowseResultsRenderer': {
          'secondaryContents': {
            'sectionListRenderer': {
              'contents': [
                {
                  'musicPlaylistShelfRenderer': {'contents': first},
                },
              ],
              if (owned)
                'continuations': [
                  {
                    'nextContinuationData': {'continuation': 'suggestions'},
                  },
                ],
            },
          },
        },
      },
    };
  }

  /// Songs per page (YouTube's is 100).
  var pageSize = 100;

  Map<String, Object> _more(String playlist, int from) => {
    'continuationItemRenderer': {
      'continuationEndpoint': {
        'continuationCommand': {'token': 'page:$playlist:$from'},
      },
    },
  };

  /// The next page of a playlist, or its suggestions.
  Object continuation(String token) {
    if (token == 'suggestions') {
      return {
        'continuationContents': {
          'sectionListContinuation': {
            'contents': [
              {
                'musicShelfRenderer': {
                  'title': _runs('Suggestions'),
                  'contents': [_row('suggested1', null), _row('suggested2', null)],
                },
              },
            ],
          },
        },
      };
    }
    final [_, id, from] = token.split(':');
    final p = id == 'LM' ? null : playlists[id];
    final songs = p?.songs ?? liked;
    final start = int.parse(from);
    final rows = [
      for (var i = start; i < songs.length && i < start + pageSize; i++)
        _row(songs[i], p?.entries[i].setId),
    ];
    if (start + pageSize < songs.length) rows.add(_more(id, start + pageSize));
    return {
      'onResponseReceivedActions': [
        {
          'appendContinuationItemsAction': {'continuationItems': rows},
        },
      ],
    };
  }

  static Map<String, Object> _row(String videoId, String? setId) => {
    'musicResponsiveListItemRenderer': {
      'playlistItemData': {
        'videoId': videoId,
        'playlistSetVideoId': ?setId,
      },
      'flexColumns': [
        {
          'musicResponsiveListItemFlexColumnRenderer': {
            'text': _runs('Song $videoId'),
          },
        },
        {
          'musicResponsiveListItemFlexColumnRenderer': {
            'text': _runs('Artist'),
          },
        },
      ],
    },
  };
}
