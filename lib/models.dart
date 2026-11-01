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
  });

  final String id;
  final String name;
  final List<Track> tracks;

  /// Where it was imported from, e.g. "Spotify".
  final String? source;

  Playlist copyWith({String? name, List<Track>? tracks}) => Playlist(
    id: id,
    name: name ?? this.name,
    tracks: tracks ?? this.tracks,
    source: source,
  );

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
    id: json['id'],
    name: json['name'],
    tracks: [for (final t in json['tracks'] as List? ?? []) Track.fromJson(t)],
    source: json['source'],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'tracks': tracks,
    'source': source,
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
  });

  final String title;
  final String subtitle;
  final String artUrl;
  final List<Track> tracks;
  final String? artist;
  final String? artistId;
}

class Artist {
  const Artist({
    required this.name,
    required this.subtitle,
    required this.artUrl,
    required this.topSongs,
    required this.shelves,
  });

  final String name;
  final String subtitle;
  final String artUrl;
  final List<Track> topSongs;
  final List<Shelf> shelves;
}
