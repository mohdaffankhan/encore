class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    this.artistId,
    this.album,
    this.albumId,
    this.duration,
    required this.artUrl,
  });

  final String id;
  final String title;
  final String artist;
  final String? artistId;
  final String? album;
  final String? albumId;
  final Duration? duration;
  final String artUrl;

  factory Track.fromJson(Map<String, dynamic> json) => Track(
    id: json['id'],
    title: json['title'],
    artist: json['artist'],
    artistId: json['artistId'],
    album: json['album'],
    albumId: json['albumId'],
    duration: json['duration'] == null
        ? null
        : Duration(seconds: json['duration']),
    artUrl: json['artUrl'],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'artistId': artistId,
    'album': album,
    'albumId': albumId,
    'duration': duration?.inSeconds,
    'artUrl': artUrl,
  };

  @override
  bool operator ==(Object other) => other is Track && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A playlist made in Encore (or imported into it), kept on the device.
class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    this.tracks = const [],
    this.source,
    this.remoteId,
  });

  final String id;
  final String name;
  final List<Track> tracks;

  /// Where it was imported from, e.g. "Spotify".
  final String? source;

  /// Signed in: the account's playlist it is kept in sync with.
  final String? remoteId;

  Playlist copyWith({
    String? name,
    List<Track>? tracks,
    String? remoteId,
    bool unlink = false,
  }) => Playlist(
    id: id,
    name: name ?? this.name,
    tracks: tracks ?? this.tracks,
    source: source,
    remoteId: unlink ? null : remoteId ?? this.remoteId,
  );

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
    id: json['id'],
    name: json['name'],
    tracks: [for (final t in json['tracks'] as List? ?? []) Track.fromJson(t)],
    source: json['source'],
    remoteId: json['remoteId'] is String ? json['remoteId'] : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'tracks': tracks,
    'source': source,
    'remoteId': ?remoteId,
  };
}

enum MediaKind { album, playlist, artist }

/// A link to an album, playlist or artist page.
class MediaRef {
  const MediaRef({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.artUrl,
  });

  final MediaKind kind;

  /// The YouTube Music browse id (`MPRE…`, `VL…` or `UC…`).
  final String id;
  final String title;
  final String subtitle;
  final String artUrl;

  MediaRef withId(String id) => MediaRef(
    kind: kind,
    id: id,
    title: title,
    subtitle: subtitle,
    artUrl: artUrl,
  );

  factory MediaRef.fromJson(Map<String, dynamic> json) => MediaRef(
    kind: MediaKind.values.byName(json['kind']),
    id: json['id'],
    title: json['title'],
    subtitle: json['subtitle'],
    artUrl: json['artUrl'],
  );

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'artUrl': artUrl,
  };
}

/// A titled row: songs shown as a list, and/or cards (albums, playlists,
/// artists, or videos as [Track]s).
class Shelf {
  const Shelf(this.title, {this.tracks = const [], this.cards = const []});

  final String title;
  final List<Track> tracks;
  final List<Object> cards;

  /// Cards are told apart by `kind`, which only a [MediaRef] has.
  factory Shelf.fromJson(Map<String, dynamic> json) => Shelf(
    json['title'],
    tracks: [for (final t in json['tracks'] as List) Track.fromJson(t)],
    cards: [
      for (final c in json['cards'] as List)
        c['kind'] == null ? Track.fromJson(c) : MediaRef.fromJson(c),
    ],
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'tracks': tracks,
    'cards': cards,
  };
}

/// An album or playlist page.
class Collection {
  const Collection({
    required this.title,
    required this.subtitle,
    required this.artUrl,
    required this.tracks,
    this.artist,
    this.artistId,
    this.playlistId,
    this.saved,
    this.owned = false,
    this.entryIds = const {},
  });

  final String title;
  final String subtitle;
  final String artUrl;
  final List<Track> tracks;
  final String? artist;
  final String? artistId;

  /// The playlist behind it on YouTube (an album's is `OLAK…`), which is
  /// what saving it to the library saves.
  final String? playlistId;

  /// Signed in: whether it is saved in the account's library (null when
  /// not signed in, or the page doesn't say).
  final bool? saved;

  /// Signed in: a playlist the account made (it can be edited).
  final bool owned;

  /// Each song's entry in the playlist (its `setVideoId`), by video id:
  /// what YouTube needs to remove or move it.
  final Map<String, List<String>> entryIds;
}

class Artist {
  const Artist({
    required this.name,
    required this.subtitle,
    required this.artUrl,
    required this.topSongs,
    required this.shelves,
    this.channelId,
    this.subscribed,
    this.radio,
  });

  final String name;
  final String subtitle;
  final String artUrl;
  final List<Track> topSongs;
  final List<Shelf> shelves;

  /// The channel following subscribes to (not always the page's id).
  final String? channelId;

  /// Signed in: whether the account follows the artist.
  final bool? subscribed;

  /// The artist's own radio (YouTube Music's "Mix", `RDEM…`): where it
  /// starts, the playlist and its parameters for `next`.
  final ({String videoId, String playlistId, String? params})? radio;
}

/// How good songs sound, against how much data they use.
enum AudioQuality {
  /// The best there is (about 130–160 kbps).
  high('High', 'Best sound'),

  /// About 70 kbps: sounds fine, about half the data.
  normal('Normal', 'About half the data'),

  /// The least data (about 50 kbps).
  low('Low', 'Least data');

  const AudioQuality(this.label, this.detail);

  final String label;
  final String detail;
}

/// The signed-in YouTube account, as shown in Settings.
class AccountInfo {
  const AccountInfo({required this.name, this.handle = '', this.photoUrl = ''});

  final String name;

  /// e.g. @someone (empty for accounts without a channel).
  final String handle;
  final String photoUrl;

  Map<String, Object> toJson() => {
    'name': name,
    'handle': handle,
    'photoUrl': photoUrl,
  };

  static AccountInfo? fromJson(Object? json) => switch (json) {
    {'name': final String name} when name.isNotEmpty => AccountInfo(
      name: name,
      handle: json['handle'] is String ? json['handle'] as String : '',
      photoUrl: json['photoUrl'] is String ? json['photoUrl'] as String : '',
    ),
    _ => null,
  };

  @override
  bool operator ==(Object other) =>
      other is AccountInfo &&
      other.name == name &&
      other.handle == handle &&
      other.photoUrl == photoUrl;

  @override
  int get hashCode => Object.hash(name, handle, photoUrl);
}

/// A channel an account can use YouTube Music as.
class AccountChannel {
  const AccountChannel({
    required this.name,
    this.handle = '',
    this.photoUrl = '',
    this.pageId,
    this.selected = false,
  });

  final String name;
  final String handle;
  final String photoUrl;

  /// A brand channel's id (sent as X-Goog-PageId); null for the account's
  /// own channel.
  final String? pageId;
  final bool selected;
}
