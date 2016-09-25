/*
 *  $Id: Track.h 1387 2009-07-17 20:18:40Z stephen_booth $
 *
 *  Copyright (C) 2005 - 2007 Stephen F. Booth <me@sbooth.org>
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

#import <Cocoa/Cocoa.h>

#import "AudioMetadata.h"

@class CompactDiscDocument;

@interface Track : NSObject <NSCopying>
{
	CompactDiscDocument		*_document;

	BOOL					_ripInProgress;
	unsigned				_activeEncoders;

	// View properties
	BOOL					_selected;
	
	// Metadata information
	NSString				*_title;
	NSString				*_artist;
	NSString 				*_date;
	NSString				*_genre;
	NSString				*_composer;
	NSString				*_comment;

	// MusicBrainz identifiers
	NSString				*_musicbrainzTrackId;
	NSString				*_musicbrainzArtistId;
	
	// Physical track properties
	unsigned 				_number;
	unsigned				_firstSector;
	unsigned				_lastSector;
	unsigned 				_channels;
	BOOL					_preEmphasis;
	BOOL					_copyPermitted;
	NSString				*_ISRC;
	BOOL					_dataTrack;
}

- (CompactDiscDocument *)	document;
- (void)					setDocument:(CompactDiscDocument *)document;

- (NSString *)		length;

- (BOOL)			ripInProgress;
- (void)			setRipInProgress:(BOOL)ripInProgress;

- (BOOL)			encodeInProgress;
- (void)			encodeStarted;
- (void)			encodeCompleted;

- (BOOL)			selected;
- (void)			setSelected:(BOOL)selected;

- (NSString *)		title;
- (void)			setTitle:(NSString *)title;

- (NSString *)		artist;
- (void)			setArtist:(NSString *)artist;

- (NSString *)		date;
- (void)			setDate:(NSString *)date;

- (NSString *)		genre;
- (void)			setGenre:(NSString *)genre;

- (NSString *)		composer;
- (void)			setComposer:(NSString *)composer;

- (NSString *)		comment;
- (void)			setComment:(NSString *)comment;

- (unsigned)		byteSize;

- (unsigned)		minute;
- (unsigned)		second;
- (unsigned)		frame;

- (unsigned)		number;
- (void)			setNumber:(unsigned)number;

- (unsigned)		firstSector;
- (void)			setFirstSector:(unsigned)firstSector;

- (unsigned)		lastSector;
- (void)			setLastSector:(unsigned)lastSector;

- (unsigned)		channels;
- (void)			setChannels:(unsigned)channels;

- (BOOL)			preEmphasis;
- (void)			setPreEmphasis:(BOOL)preEmphasis;

- (BOOL)			copyPermitted;
- (void)			setCopyPermitted:(BOOL)copyPermitted;

- (NSString *)		ISRC;
- (void)			setISRC:(NSString *)ISRC;

- (NSString *)	    musicbrainzTrackId;
- (void)		    setMusicbrainzTrackId:(NSString *)musicbrainzTrackId;

- (NSString *)	    musicbrainzArtistId;
- (void)		    setMusicbrainzArtistId:(NSString *)musicbrainzArtistId;

- (BOOL)			dataTrack;
- (void)			setDataTrack:(BOOL)dataTrack;

// Metadata access
- (AudioMetadata *)			metadata;

// Save/Restore
- (NSDictionary *)	getDictionary;
- (void)			setPropertiesFromDictionary:(NSDictionary *)properties;

@end
