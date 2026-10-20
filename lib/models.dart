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
}

/// A titled row: songs shown as a list, and/or cards (albums, playlists,
/// artists, or videos as [Track]s).
class Shelf {
  const Shelf(this.title, {this.tracks = const [], this.cards = const []});

  final String title;
  final List<Track> tracks;
  final List<Object> cards;
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
