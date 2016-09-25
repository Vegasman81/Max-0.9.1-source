/*
 *  $Id: CoreAudioEncoderTask.mm 1390 2009-08-27 15:29:21Z stephen_booth $
 *
 *  Copyright (C) 2005 - 2009 Stephen F. Booth <me@sbooth.org>
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

#import "CoreAudioEncoderTask.h"
#import "CoreAudioEncoder.h"
#import "CoreAudioUtilities.h"
#import "LogController.h"
#import "UtilityFunctions.h"
#import "Genres.h"

#include <AudioToolbox/AudioFile.h>
#include <AudioToolbox/AudioFormat.h>

#include <mp4v2/mp4.h>

#include <taglib/aifffile.h>
#include <taglib/wavfile.h>
#include <taglib/tag.h>						// TagLib::Tag
#include <taglib/tstring.h>					// TagLib::String
#include <taglib/tbytevector.h>				// TagLib::ByteVector
#include <taglib/textidentificationframe.h>	// TagLib::ID3V2::TextIdentificationFrame
#include <taglib/uniquefileidentifierframe.h> // TagLib::ID3V2::UniqueFileIdentifierFrame
#include <taglib/attachedpictureframe.h>	// TagLib::ID3V2::AttachedPictureFrame
#include <taglib/id3v2tag.h>				// TagLib::ID3V2::Tag

@interface CoreAudioEncoderTask (Private)
-(void) writeMPEG4Tags;
-(void) writeAIFFTags;
-(void) writeWAVETags;
@end

@implementation CoreAudioEncoderTask

- (id) init
{
	if((self = [super init])) {
		_encoderClass	= [CoreAudioEncoder class];
		return self;
	}
	return nil;
}

- (void) writeTags
{
	AudioFileTypeID			fileType				= [self fileType];

	// Use mp4v2 for mp4/m4a files
	if(kAudioFileMPEG4Type == fileType || kAudioFileM4AType == fileType)
		[self writeMPEG4Tags];
	else if(kAudioFileAIFFType == fileType)
		[self writeAIFFTags];
	else if(kAudioFileWAVEType == fileType)
		[self writeWAVETags];
	// Use (unimplemented as of 10.4.3) CoreAudio metadata functions
	else {
		OSStatus				err;
		FSRef					ref;
		AudioFileID				fileID;
		NSMutableDictionary		*info;
		UInt32					size;
		AudioMetadata			*metadata				= [[self taskInfo] metadata];
		NSString				*bundleVersion			= nil;
		NSNumber				*trackNumber			= nil;
		NSString				*album					= nil;
		NSString				*artist					= nil;
		NSString				*composer				= nil;
		NSString				*title					= nil;
		NSString				*year					= nil;
		NSString				*genre					= nil;
		NSString				*comment				= nil;
		NSString				*trackComment			= nil;
		
		@try {
			err = FSPathMakeRef((const UInt8 *)[[self outputFilename] fileSystemRepresentation], &ref, NULL);
			NSAssert1(noErr == err, NSLocalizedStringFromTable(@"Unable to locate the output file.", @"Exceptions", @""), UTCreateStringForOSType(err));
			
			err = AudioFileOpen(&ref, fsRdWrPerm, [self fileType], &fileID);
			NSAssert2(noErr == err, NSLocalizedStringFromTable(@"The call to %@ failed.", @"Exceptions", @""), @"AudioFileOpen", UTCreateStringForOSType(err));
			
			// Get the dictionary and set properties
			size = sizeof(info);
			err = AudioFileGetProperty(fileID, kAudioFilePropertyInfoDictionary, &size, &info);
			//		NSLog(@"error is %@", UTCreateStringForOSType(err));
			if(noErr == err) {
				
				bundleVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
				[info setObject:[NSString stringWithFormat:@"Max %@", bundleVersion] forKey:@kAFInfoDictionary_EncodingApplication];
				
				// Album title
				album = [metadata albumTitle];
				if(nil != album)
					[info setObject:album forKey:@kAFInfoDictionary_Album];
				
				// Artist
				artist = [metadata trackArtist];
				if(nil == artist)
					artist = [metadata albumArtist];
				if(nil != artist)
					[info setObject:artist forKey:@kAFInfoDictionary_Artist];
				
				// Composer
				composer = [metadata trackComposer];
				if(nil == composer)
					composer = [metadata albumComposer];
				if(nil != composer)
					[info setObject:composer forKey:@kAFInfoDictionary_Composer];

				// Genre
				if(nil != [[self taskInfo] inputTracks] && 1 == [[[self taskInfo] inputTracks] count])
					genre = [metadata trackGenre];
				if(nil == genre)
					genre = [metadata albumGenre];
				if(nil != genre)
					[info setObject:genre forKey:@kAFInfoDictionary_Genre];
				
				// Year
				year = [metadata trackDate];
				if(nil == year)
					year = [metadata albumDate];
				if(nil != year)
					[info setObject:year forKey:@kAFInfoDictionary_Year];
				
				// Comment
				comment			= [metadata albumComment];
				trackComment	= [metadata trackComment];
				if(nil != trackComment)
					comment = (nil == comment ? trackComment : [NSString stringWithFormat:@"%@\n%@", trackComment, comment]);
				if([[[[self taskInfo] settings] objectForKey:@"saveSettingsInComment"] boolValue])
					comment = (nil == comment ? [self encoderSettingsString] : [comment stringByAppendingString:[NSString stringWithFormat:@"\n%@", [self encoderSettingsString]]]);
				if(nil != comment)
					[info setObject:comment forKey:@kAFInfoDictionary_Comments];
				
				// Track title
				title = [metadata trackTitle];
				if(nil != title)
					[info setObject:title forKey:@kAFInfoDictionary_Title];
				
				// Track number
				trackNumber = [metadata trackNumber];
				if(nil != trackNumber)
					[info setObject:trackNumber forKey:@kAFInfoDictionary_TrackNumber];
				
				// On 10.4.8, this returns a 'pty?' error- must not be settable
				/*
				size	= sizeof(info);
				err		= AudioFileSetProperty(fileID, kAudioFilePropertyInfoDictionary, size, &info);
				NSAssert2(noErr == err, NSLocalizedStringFromTable(@"The call to %@ failed.", @"Exceptions", @""), @"AudioFileSetProperty", UTCreateStringForOSType(err));
				 */
			}
		}
				
		@finally {
			// Clean up	
			err = AudioFileClose(fileID);
			NSAssert2(noErr == err, NSLocalizedStringFromTable(@"The call to %@ failed.", @"Exceptions", @""), @"AudioFileClose", UTCreateStringForOSType(err));
		}
	}	
}

- (NSString *) fileExtension
{
	NSArray		*extensions		= [[self encoderSettings] objectForKey:@"extensionsForType"];
	
	return [extensions objectAtIndex:[[[self encoderSettings] objectForKey:@"extensionIndex"] unsignedIntValue]];
}

- (NSString *) outputFormatName
{
	return getCoreAudioOutputFormatName([self fileType], [self formatID], [[[self encoderSettings] objectForKey:@"formatFlags"] unsignedLongValue]);
}

- (AudioFileTypeID)		fileType		{ return [[[self encoderSettings] objectForKey:@"fileType"] unsignedLongValue]; }
- (UInt32)				formatID		{ return [[[self encoderSettings] objectForKey:@"formatID"] unsignedLongValue]; }

@end

@implementation CoreAudioEncoderTask (CueSheetAdditions)

- (NSString *) cueSheetFormatName
{
 	switch([self fileType]) {
		case kAudioFileWAVEType:	return @"WAVE";				break;
		case kAudioFileAIFFType:	return @"AIFF";				break;
		case kAudioFileMP3Type:		return @"MP3";				break;
		default:					return nil;					break;
	}
}

- (BOOL) formatIsValidForCueSheet
{
 	switch([self fileType]) {
		case kAudioFileWAVEType:	return YES;					break;
		case kAudioFileAIFFType:	return YES;					break;
		case kAudioFileMP3Type:		return YES;					break;
		default:					return NO;					break;
	}
}

@end

@implementation CoreAudioEncoderTask (iTunesAdditions)

- (BOOL)			formatIsValidForiTunes
{
 	switch([self fileType]) {
		case kAudioFileWAVEType:	return YES;					break;
		case kAudioFileAIFFType:	return YES;					break;
		case kAudioFileM4AType:		return YES;					break;
		case kAudioFileMP3Type:		return YES;					break;
		default:					return NO;					break;
	}
}

@end

@implementation CoreAudioEncoderTask (Private)

-(void) writeMPEG4Tags
{
	MP4FileHandle			mp4FileHandle;
	AudioMetadata			*metadata				= [[self taskInfo] metadata];
	NSString				*bundleVersion			= nil;
	NSString				*versionString			= nil;
	NSNumber				*trackNumber			= nil;
	NSNumber				*trackTotal				= nil;
	NSNumber				*discNumber				= nil;
	NSNumber				*discTotal				= nil;
	NSString				*album					= nil;
	NSString				*artist					= nil;
	NSString				*albumArtist			= nil;
	NSString				*composer				= nil;
	NSString				*title					= nil;
	NSString				*year					= nil;
	NSString				*genre					= nil;
	NSString				*comment				= nil;
	NSString				*trackComment			= nil;
	NSNumber				*compilation			= nil;
	NSImage					*albumArt				= nil;
	NSData					*data					= nil;
	NSString				*tempFilename			= NULL;

	mp4FileHandle = MP4Modify([[self outputFilename] fileSystemRepresentation], 0, 0);
	NSAssert(MP4_INVALID_FILE_HANDLE != mp4FileHandle, NSLocalizedStringFromTable(@"Unable to open the output file for tagging.", @"Exceptions", @""));
	
	// Album title
	album = [metadata albumTitle];
	if(nil != album)
		MP4SetMetadataAlbum(mp4FileHandle, [album UTF8String]);
	
	// Artist
	artist = [metadata trackArtist];
	if(nil == artist)
		artist = [metadata albumArtist];
	if(nil != artist)
		MP4SetMetadataArtist(mp4FileHandle, [artist UTF8String]);
	
	// Album artist
	albumArtist = [metadata albumArtist];
	if(nil != albumArtist)
		MP4SetMetadataAlbumArtist(mp4FileHandle, [albumArtist UTF8String]);
	
	// Composer
	composer = [metadata trackComposer];
	if(nil == composer)
		composer = [metadata albumComposer];
	if(nil != composer)
		MP4SetMetadataWriter(mp4FileHandle, [composer UTF8String]);
	
	// Genre
	if(nil != [[self taskInfo] inputTracks] && 1 == [[[self taskInfo] inputTracks] count])
		genre = [metadata trackGenre];
	if(nil == genre)
		genre = [metadata albumGenre];
	if(nil != genre)
		MP4SetMetadataGenre(mp4FileHandle, [genre UTF8String]);
	
	// Year
	year = [metadata trackDate];
	if(nil == year)
		year = [metadata albumDate];
	if(nil != year)
		MP4SetMetadataYear(mp4FileHandle, [year UTF8String]);
	
	// Comment
	comment			= [metadata albumComment];
	trackComment	= [metadata trackComment];
	if(nil != trackComment)
		comment = (nil == comment ? trackComment : [NSString stringWithFormat:@"%@\n%@", trackComment, comment]);
	if([[[[self taskInfo] settings] objectForKey:@"saveSettingsInComment"] boolValue])
		comment = (nil == comment ? [self encoderSettingsString] : [NSString stringWithFormat:@"%@\n%@", comment, [self encoderSettingsString]]);
	if(nil != comment)
		MP4SetMetadataComment(mp4FileHandle, [comment UTF8String]);
	
	// Track title
	title = [metadata trackTitle];
	if(nil != title)
		MP4SetMetadataName(mp4FileHandle, [title UTF8String]);
	
	// Track number
	trackNumber = [metadata trackNumber];
	trackTotal = [metadata trackTotal];
	if(nil != trackNumber && nil != trackTotal)
		MP4SetMetadataTrack(mp4FileHandle, [trackNumber intValue], [trackTotal intValue]);
	else if(nil != trackNumber)
		MP4SetMetadataTrack(mp4FileHandle, [trackNumber intValue], 0);
	else if(0 != trackTotal)
		MP4SetMetadataTrack(mp4FileHandle, 0, [trackTotal intValue]);
	
	// Disc number
	discNumber = [metadata discNumber];
	discTotal = [metadata discTotal];
	if(nil != discNumber && nil != discTotal)
		MP4SetMetadataDisk(mp4FileHandle, [discNumber intValue], [discTotal intValue]);
	else if(0 != discNumber)
		MP4SetMetadataDisk(mp4FileHandle, [discNumber intValue], 0);
	else if(0 != discTotal)
		MP4SetMetadataDisk(mp4FileHandle, 0, [discTotal intValue]);
	
	// Compilation
	compilation = [metadata compilation];
	if(nil != compilation) {
		MP4SetMetadataCompilation(mp4FileHandle, [compilation boolValue]);
	}
	
	// Album art
	albumArt = [metadata albumArt];
	if(nil != albumArt) {
		data = getPNGDataForImage(albumArt); 
		MP4SetMetadataCoverArt(mp4FileHandle, (u_int8_t *)[data bytes], [data length]);
	}
	
	// Encoded by
	bundleVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
	versionString = [NSString stringWithFormat:@"Max %@", bundleVersion];
	MP4SetMetadataTool(mp4FileHandle, [versionString UTF8String]);
	
	MP4Close(mp4FileHandle);
	
	// Optimize the atoms so the MP4 files will play on shared iTunes libraries
	// mp4v2 creates a temp file in ., so use a custom file and manually rename it	
	tempFilename = generateTemporaryFilename([[[self taskInfo] settings] objectForKey:@"temporaryDirectory"], [self fileExtension]);
	
	if(MP4Optimize([[self outputFilename] fileSystemRepresentation], [tempFilename fileSystemRepresentation], 0)) {
		NSFileManager	*fileManager	= [NSFileManager defaultManager];
		
		// Delete the existing output file
		if([fileManager removeFileAtPath:[self outputFilename] handler:nil]) {
			if(NO == [fileManager movePath:tempFilename toPath:[self outputFilename] handler:nil]) {
				[[LogController sharedController] logMessage:[NSString stringWithFormat:NSLocalizedStringFromTable(@"Warning: the file %@ was lost.", @"Exceptions", @""), [[NSFileManager defaultManager] displayNameAtPath:[self outputFilename]]]];
			}
		}
		else {
			[[LogController sharedController] logMessage:NSLocalizedStringFromTable(@"Unable to delete the output file.", @"Exceptions", @"")];
		}
	}
	else {
		[[LogController sharedController] logMessage:[NSString stringWithFormat:NSLocalizedStringFromTable(@"Unable to optimize file: %@", @"General", @""), [[NSFileManager defaultManager] displayNameAtPath:[self outputFilename]]]];
	}
}

-(void) writeAIFFTags
{
	AudioMetadata								*metadata					= [[self taskInfo] metadata];
	NSNumber									*trackNumber				= nil;
	NSNumber									*trackTotal					= nil;
	NSString									*album						= nil;
	NSString									*artist						= nil;
	NSString									*composer					= nil;
	NSString									*title						= nil;
	NSString									*year						= nil;
	NSString									*genre						= nil;
	NSString									*comment					= nil;
	NSString									*trackComment				= nil;
	NSNumber									*compilation				= nil;
	NSNumber									*discNumber					= nil;
	NSNumber									*discTotal					= nil;
	NSNumber									*length						= nil;
	TagLib::ID3v2::TextIdentificationFrame		*frame						= NULL;
	TagLib::ID3v2::AttachedPictureFrame			*pictureFrame				= NULL;
	NSImage										*albumArt					= nil;
	NSData										*data						= nil;
	TagLib::RIFF::AIFF::File					f							([[self outputFilename] fileSystemRepresentation], false);
	NSString									*bundleVersion				= nil;
	NSString									*versionString				= nil;
	NSString									*timestamp					= nil;
	NSString									*mcn						= nil;
	NSString									*isrc						= nil;
	NSString									*musicbrainzDiscId			= nil;
	NSString									*musicbrainzAlbumId			= nil;
	NSString									*musicbrainzArtistId		= nil;
	NSString									*musicbrainzAlbumArtistId	= nil;
	NSString									*musicbrainzTrackId			= nil;
	unsigned									index						= NSNotFound;
	
	NSAssert(f.isValid(), NSLocalizedStringFromTable(@"Unable to open the output file for tagging.", @"Exceptions", @""));
	
	// Use UTF-8 as the default encoding
	(TagLib::ID3v2::FrameFactory::instance())->setDefaultTextEncoding(TagLib::String::UTF8);
	
	// Album title
	album = [metadata albumTitle];
	if(nil != album)
		f.tag()->setAlbum(TagLib::String([album UTF8String], TagLib::String::UTF8));
	
	// Artist
	artist = [metadata trackArtist];
	if(nil == artist)
		artist = [metadata albumArtist];
	if(nil != artist)
		f.tag()->setArtist(TagLib::String([artist UTF8String], TagLib::String::UTF8));
	
	// Composer
	composer = [metadata trackComposer];
	if(nil == composer)
		composer = [metadata albumComposer];
	if(nil != composer) {
		frame = new TagLib::ID3v2::TextIdentificationFrame("TCOM", TagLib::String::Latin1);
		NSAssert(NULL != frame, NSLocalizedStringFromTable(@"Unable to allocate memory.", @"Exceptions", @""));
		
		frame->setText(TagLib::String([composer UTF8String], TagLib::String::UTF8));
		f.tag()->addFrame(frame);
	}
	
	// Genre
	genre = [metadata trackGenre];
	if(nil == genre)
		genre = [metadata albumGenre];
  	if(nil != genre) {
 		// There is a bug in iTunes that will show numeric genres for ID3v2.4 genre tags
 		if([[NSUserDefaults standardUserDefaults] boolForKey:@"useiTunesWorkarounds"]) {
 			index = [[Genres unsortedGenres] indexOfObject:genre];
 			
 			frame = new TagLib::ID3v2::TextIdentificationFrame("TCON", TagLib::String::Latin1);
			NSAssert(NULL != frame, NSLocalizedStringFromTable(@"Unable to allocate memory.", @"Exceptions", @""));
			
 			// Only use numbers for the original ID3v1 genre list
 			if(NSNotFound == index)
 				frame->setText(TagLib::String([genre UTF8String], TagLib::String::UTF8));
 			else
 				frame->setText(TagLib::String([[NSString stringWithFormat:@"(%u)", index] UTF8String], TagLib::String::UTF8));
 			
 			f.tag()->addFrame(frame);
 		}
 		else
 			f.tag()->setGenre(TagLib::String([genre UTF8String], TagLib::String::UTF8));
  	}
	
	// Year
	year = [metadata trackDate];
	if(nil == year)
		year = [metadata albumDate];
	if(nil != year)
		f.tag()->setYear([year intValue]);
	
	// Comment
	comment			= [metadata albumComment];
	trackComment	= [metadata trackComment];
	if(nil != trackComment)
		comment = (nil == comment ? trackComment : [NSString stringWithFormat:@"%@\n%@", trackComment, comment]);
	if([[[[self taskInfo] settings] objectForKey:@"saveSettingsInComment"] boolValue])
		comment = (nil == comment ? [self encoderSettingsString] : [NSString stringWithFormat:@"%@\n%@", comment, [self encoderSettingsString]]);
	if(nil != comment)
		f.tag()->setComment(TagLib::String([comment UTF8String], TagLib::String::UTF8));
	
	// Track title
	title = [metadata trackTitle];
	if(nil != title)
		f.tag()->setTitle(TagLib::String([title UTF8String], TagLib::String::UTF8));
	
	// Track number
	trackNumber		= [metadata trackNumber];
	trackTotal		= [metadata trackTotal];
	if(nil != trackTotal) {
		frame = new TagLib::ID3v2::TextIdentificationFrame("TRCK", TagLib::String::Latin1);
		NSAssert(NULL != frame, NSLocalizedStringFromTable(@"Unable to allocate memory.", @"Exceptions", @""));
		
		frame->setText(TagLib::String([[NSString stringWithFormat:@"%u/%u", [trackNumber intValue], [trackTotal intValue]] UTF8String], TagLib::String::UTF8));
		f.tag()->addFrame(frame);
	}
	else if(nil != trackNumber)
		f.tag()->setTrack([trackNumber intValue]);
	
	// Multi-artist (compilation)
	// iTunes uses the TCMP frame for this, which isn't in the standard, but we'll use it for compatibility
	compilation = [metadata compilation];
	if(nil != compilation && [[NSUserDefaults standardUserDefaults] boolForKey:@"useiTunesWorkarounds"]) {
		frame = new TagLib::ID3v2::TextIdentificationFrame("TCMP", TagLib::String::Latin1);
		NSAssert(NULL != frame, NSLocalizedStringFromTable(@"Unable to allocate memory.", @"Exceptions", @""));
		
		frame->setText(TagLib::String([[compilation stringValue] UTF8String], TagLib::String::UTF8));
		f.tag()->addFrame(frame);
	}	
	
	// Disc number
	discNumber = [metadata discNumber];
	discTotal = [metadata discTotal];
	
	if(nil != discNumber && nil != discTotal) {
		frame = new TagLib::ID3v2::TextIdentificationFrame("TPOS", TagLib::String::Latin1);
		NSAssert(NULL != frame, NSLocalizedStringFromTable(@"Unable to allocate memory.", @"Exceptions", @""));
		
		frame->setText(TagLib::String([[NSString stringWithFormat:@"%u/%u", [discNumber intValue], [discTotal intValue]] UTF8String], TagLib::String::UTF8));
		f.tag()->addFrame(frame);
	}
	else if(nil != discNumber) {
		frame = new TagLib::ID3v2::TextIdentificationFrame("TPOS", TagLib::String::Latin1);
		NSAssert(NULL != frame, NSLocalizedStringFromTable(@"Unable to allocate memory.", @"Exceptions", @""));
		
		frame->setText(TagLib::String([[NSString stringWithFormat:@"%u", [discNumber intValue]] UTF8String], TagLib::String::UTF8));
		f.tag()->addFrame(frame);
	}
	else if(nil != discTotal) {
		frame = new TagLib::ID3v2::TextIdentificationFrame("TPOS", TagLib::String::Latin1);
		NSAssert(NULL != frame, NSLocalizedStringFromTable(@"Unable to allocate memory.", @"Exceptions", @""));
		
		frame->setText(TagLib::String([[NSString stringWithFormat:@"/@u", [discTotal intValue]] UTF8String], TagLib::String::UTF8));
		f.tag()->addFrame(frame);
	}
	
	// Track length
	length = [metadata length];
	if(nil != [[self taskInfo] inputTracks]) {		
		// Sum up length of all tracks
		unsigned minutes	= [[[[self taskInfo] inputTracks] valueForKeyPath:@"@sum.minute"] unsignedIntValue];
		unsigned seconds	= [[[[self taskInfo] inputTracks] valueForKeyPath:@"@sum.second"] unsignedIntValue];
		unsigned frames		= [[[[self taskInfo] inputTracks] valueForKeyPath:@"@sum.frame"] unsignedIntValue];
		unsigned ms			= ((60 * minutes) + seconds + (unsigned)(frames / 75.0)) * 1000;
		
		frame = new TagLib::ID3v2::TextIdentificationFrame("TLEN", TagLib::String::Latin1);
		NSAssert(NULL != frame, NSLocalizedStringFromTable(@"Unable to allocate memory.", @"Exceptions", @""));
		
		frame->setText(TagLib::String([[NSString stringWithFormat:@"%u", ms] UTF8String], TagLib::String::UTF8));
		f.tag()->addFrame(frame);
	}
	else if(nil != length) {
		frame = new TagLib::ID3v2::TextIdentificationFrame("TLEN", TagLib::String::Latin1);
		NSAssert(NULL != frame, NSLocalizedStringFromTable(@"Unable to allocate memory.", @"Exceptions", @""));
		
		frame->setText(TagLib::String([[NSString stringWithFormat:@"%u", 1000 * [length intValue]] UTF8String], TagLib::String::UTF8));
		f.tag()->addFrame(frame);
	}
	
	// Album art
	albumArt = [metadata albumArt];
	if(nil != albumArt) {
		data			= getPNGDataForImage(albumArt); 
		pictureFrame	= new TagLib::ID3v2::AttachedPictureFrame();
		NSAssert(NULL != pictureFrame, NSLocalizedStringFromTable(@"Unable to allocate memory.", @"Exceptions", @""));
		
		pictureFrame->setMimeType(TagLib::String("image/png", TagLib::String::Latin1));
		pictureFrame->setPicture(TagLib::ByteVector((const char *)[data bytes], [data length]));
		f.tag()->addFrame(pictureFrame);
	}
	
	// MCN
	mcn = [metadata MCN];
	if (nil != mcn) {
		TagLib::ID3v2::UserTextIdentificationFrame *frame = new TagLib::ID3v2::UserTextIdentificationFrame(TagLib::String::Latin1);
		NSAssert(NULL != frame, @"Unable to allocate memory.");
		frame->setDescription("MCN");
		frame->setText(TagLib::String([mcn UTF8String], TagLib::String::UTF8));
		f.tag()->addFrame(frame);
	}
	
	// ISRC
	isrc = [metadata ISRC];
	if(nil != isrc) {
		frame = new TagLib::ID3v2::TextIdentificationFrame("TSRC", TagLib::String::Latin1);
		frame->setText(TagLib::String([isrc UTF8String], TagLib::String::UTF8));
		f.tag()->addFrame(frame);
	}
	
	// MusicBrainz Artist Id
	musicbrainzArtistId = [metadata musicbrainzArtistId];
	if (nil != musicbrainzArtistId) {
		TagLib::ID3v2::UserTextIdentificationFrame *frame = new TagLib::ID3v2::UserTextIdentificationFrame(TagLib::String::Latin1);
		NSAssert(NULL != frame, @"Unable to allocate memory.");
		frame->setDescription("MusicBrainz Artist Id");
		frame->setText(TagLib::String([musicbrainzArtistId UTF8String], TagLib::String::UTF8));
		f.tag()->addFrame(frame);
	}
	
	// MusicBrainz Album Id
	musicbrainzAlbumId = [metadata musicbrainzAlbumId];
	if (nil != musicbrainzAlbumId) {
		TagLib::ID3v2::UserTextIdentificationFrame *frame = new TagLib::ID3v2::UserTextIdentificationFrame(TagLib::String::Latin1);
		NSAssert(NULL != frame, @"Unable to allocate memory.");
		frame->setDescription("MusicBrainz Album Id");
		frame->setText(TagLib::String([musicbrainzAlbumId UTF8String], TagLib::String::UTF8));
		f.tag()->addFrame(frame);
	}
	
	// MusicBrainz Album Artist Id
	musicbrainzAlbumArtistId = [metadata musicbrainzAlbumArtistId];
	if (nil != musicbrainzAlbumArtistId) {
		TagLib::ID3v2::UserTextIdentificationFrame *frame = new TagLib::ID3v2::UserTextIdentificationFrame(TagLib::String::Latin1);
		NSAssert(NULL != frame, @"Unable to allocate memory.");
		frame->setDescription("MusicBrainz Album Artist Id");
		frame->setText(TagLib::String([musicbrainzAlbumArtistId UTF8String], TagLib::String::UTF8));
		f.tag()->addFrame(frame);
	}
	
	// MusicBrainz Disc Id
	musicbrainzDiscId = [metadata discId];
	if (nil != musicbrainzDiscId) {
		TagLib::ID3v2::UserTextIdentificationFrame *frame = new TagLib::ID3v2::UserTextIdentificationFrame(TagLib::String::Latin1);
		NSAssert(NULL != frame, @"Unable to allocate memory.");
		frame->setDescription("MusicBrainz Disc Id");
		frame->setText(TagLib::String([musicbrainzDiscId UTF8String], TagLib::String::UTF8));
		f.tag()->addFrame(frame);
	}
	
	// Unique file identifier
	musicbrainzTrackId = [metadata musicbrainzTrackId];
	if (nil != musicbrainzTrackId) {
		TagLib::ID3v2::UniqueFileIdentifierFrame *frame = new TagLib::ID3v2::UniqueFileIdentifierFrame(
																									   "http://musicbrainz.org", TagLib::ByteVector([musicbrainzTrackId UTF8String])
																									   );
		NSAssert(NULL != frame, @"Unable to allocate memory.");
		f.tag()->addFrame(frame);
	}
	
	// Encoded by
	frame = new TagLib::ID3v2::TextIdentificationFrame("TENC", TagLib::String::Latin1);
	NSAssert(NULL != frame, NSLocalizedStringFromTable(@"Unable to allocate memory.", @"Exceptions", @""));
	
	bundleVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
	versionString = [NSString stringWithFormat:@"Max %@", bundleVersion];
	frame->setText(TagLib::String([versionString UTF8String], TagLib::String::UTF8));
	f.tag()->addFrame(frame);
	
	// Encoding time
	frame = new TagLib::ID3v2::TextIdentificationFrame("TDEN", TagLib::String::Latin1);
	timestamp = getID3v2Timestamp();
	NSAssert(NULL != frame, NSLocalizedStringFromTable(@"Unable to allocate memory.", @"Exceptions", @""));
	
	frame->setText(TagLib::String([timestamp UTF8String], TagLib::String::UTF8));
	f.tag()->addFrame(frame);
	
	// Tagging time
	frame = new TagLib::ID3v2::TextIdentificationFrame("TDTG", TagLib::String::Latin1);
	timestamp = getID3v2Timestamp();
	NSAssert(NULL != frame, NSLocalizedStringFromTable(@"Unable to allocate memory.", @"Exceptions", @""));
	
	frame->setText(TagLib::String([timestamp UTF8String], TagLib::String::UTF8));
	f.tag()->addFrame(frame);
	
	f.save();
}

-(void) writeWAVETags
{
	AudioMetadata								*metadata					= [[self taskInfo] metadata];
	NSNumber									*trackNumber				= nil;
	NSNumber									*trackTotal					= nil;
	NSString									*album						= nil;
	NSString									*artist						= nil;
	NSString									*composer					= nil;
	NSString									*title						= nil;
	NSString									*year						= nil;
	NSString									*genre						= nil;
	NSString									*comment					= nil;
	NSString									*trackComment				= nil;
	NSNumber									*compilation				= nil;
	NSNumber									*discNumber					= nil;
	NSNumber									*discTotal					= nil;
	NSNumber									*length						= nil;
	TagLib::ID3v2::TextIdentificationFrame		*frame						= NULL;
	TagLib::ID3v2::AttachedPictureFrame			*pictureFrame				= NULL;
	NSImage										*albumArt					= nil;
	NSData										*data						= nil;
	TagLib::RIFF::WAV::File						f							([[self outputFilename] fileSystemRepresentation], false);
	NSString									*bundleVersion				= nil;
	NSString									*versionString				= nil;
	NSString									*timestamp					= nil;
	NSString									*mcn						= nil;
	NSString									*isrc						= nil;
	NSString									*musicbrainzDiscId			= nil;
	NSString									*musicbrainzAlbumId			= nil;
	NSString									*musicbrainzArtistId		= nil;
	NSString									*musicbrainzAlbumArtistId	= nil;
	NSString									*musicbrainzTrackId			= nil;
	unsigned									index						= NSNotFound;
	
	NSAssert(f.isValid(), NSLocalizedStringFromTable(@"Unable to open the output file for tagging.", @"Exceptions", @""));
	
	// Use UTF-8 as the default encoding
	(TagLib::ID3v2::FrameFactory::instance())->setDefaultTextEncoding(TagLib::String::UTF8);
	
	// Album title
	album = [metadata albumTitle];
	if(nil != album)
		f.tag()->setAlbum(TagLib::String([album UTF8String], TagLib::String::UTF8));
	
	// Artist
	artist = [metadata trackArtist];
	if(nil == artist)
		artist = [metadata albumArtist];
	if(nil != artist)
		f.tag()->setArtist(TagLib::String([artist UTF8String], TagLib::String::UTF8));
	
	// Composer
	composer = [metadata trackComposer];
	if(nil == composer)
		composer = [metadata albumComposer];
	if(nil != composer) {
		frame = new TagLib::ID3v2::TextIdentificationFrame("TCOM", TagLib::String::Latin1);
		NSAssert(NULL != frame, NSLocalizedStringFromTable(@"Unable to allocate memory.", @"Exceptions", @""));
		
		frame->setText(TagLib::String([composer UTF8String], TagLib::String::UTF8));
		f.tag()->addFrame(frame);
	}
	
	// Genre
	genre = [metadata trackGenre];
	if(nil == genre)
		genre = [metadata albumGenre];
  	if(nil != genre) {
 		// There is a bug in iTunes that will show numeric genres for ID3v2.4 genre tags
 		if([[NSUserDefaults standardUserDefaults] boolForKey:@"useiTunesWorkarounds"]) {
 			index = [[Genres unsortedGenres] indexOfObject:genre];
 			
 			frame = new TagLib::ID3v2::TextIdentificationFrame("TCON", TagLib::String::Latin1);
			NSAssert(NULL != frame, NSLocalizedStringFromTable(@"Unable to allocate memory.", @"Exceptions", @""));
			
 			// Only use numbers for the original ID3v1 genre list
 			if(NSNotFound == index)
 				frame->setText(TagLib::String([genre UTF8String], TagLib::String::UTF8));
 			else
 				frame->setText(TagLib::String([[NSString stringWithFormat:@"(%u)", index] UTF8String], TagLib::String::UTF8));
 			
 			f.tag()->addFrame(frame);
 		}
 		else
 			f.tag()->setGenre(TagLib::String([genre UTF8String], TagLib::String::UTF8));
  	}
	
	// Year
	year = [metadata trackDate];
	if(nil == year)
		year = [metadata albumDate];
	if(nil != year)
		f.tag()->setYear([year intValue]);
	
	// Comment
	comment			= [metadata albumComment];
	trackComment	= [metadata trackComment];
	if(nil != trackComment)
		comment = (nil == comment ? trackComment : [NSString stringWithFormat:@"%@\n%@", trackComment, comment]);
	if([[[[self taskInfo] settings] objectForKey:@"saveSettingsInComment"] boolValue])
		comment = (nil == comment ? [self encoderSettingsString] : [NSString stringWithFormat:@"%@\n%@", comment, [self encoderSettingsString]]);
	if(nil != comment)
		f.tag()->setComment(TagLib::String([comment UTF8String], TagLib::String::UTF8));
	
	// Track title
	title = [metadata trackTitle];
	if(nil != title)
		f.tag()->setTitle(TagLib::String([title UTF8String], TagLib::String::UTF8));
	
	// Track number
	trackNumber		= [metadata trackNumber];
	trackTotal		= [metadata trackTotal];
	if(nil != trackTotal) {
		frame = new TagLib::ID3v2::TextIdentificationFrame("TRCK", TagLib::String::Latin1);
		NSAssert(NULL != frame, NSLocalizedStringFromTable(@"Unable to allocate memory.", @"Exceptions", @""));
		
		frame->setText(TagLib::String([[NSString stringWithFormat:@"%u/%u", [trackNumber intValue], [trackTotal intValue]] UTF8String], TagLib::String::UTF8));
		f.tag()->addFrame(frame);
	}
	else if(nil != trackNumber)
		f.tag()->setTrack([trackNumber intValue]);
	
	// Multi-artist (compilation)
	// iTunes uses the TCMP frame for this, which isn't in the standard, but we'll use it for compatibility
	compilation = [metadata compilation];
	if(nil != compilation && [[NSUserDefaults standardUserDefaults] boolForKey:@"useiTunesWorkarounds"]) {
		frame = new TagLib::ID3v2::TextIdentificationFrame("TCMP", TagLib::String::Latin1);
		NSAssert(NULL != frame, NSLocalizedStringFromTable(@"Unable to allocate memory.", @"Exceptions", @""));
		
		frame->setText(TagLib::String([[compilation stringValue] UTF8String], TagLib::String::UTF8));
		f.tag()->addFrame(frame);
	}	
	
	// Disc number
	discNumber = [metadata discNumber];
	discTotal = [metadata discTotal];
	
	if(nil != discNumber && nil != discTotal) {
		frame = new TagLib::ID3v2::TextIdentificationFrame("TPOS", TagLib::String::Latin1);
		NSAssert(NULL != frame, NSLocalizedStringFromTable(@"Unable to allocate memory.", @"Exceptions", @""));
		
		frame->setText(TagLib::String([[NSString stringWithFormat:@"%u/%u", [discNumber intValue], [discTotal intValue]] UTF8String], TagLib::String::UTF8));
		f.tag()->addFrame(frame);
	}
	else if(nil != discNumber) {
		frame = new TagLib::ID3v2::TextIdentificationFrame("TPOS", TagLib::String::Latin1);
		NSAssert(NULL != frame, NSLocalizedStringFromTable(@"Unable to allocate memory.", @"Exceptions", @""));
		
		frame->setText(TagLib::String([[NSString stringWithFormat:@"%u", [discNumber intValue]] UTF8String], TagLib::String::UTF8));
		f.tag()->addFrame(frame);
	}
	else if(nil != discTotal) {
		frame = new TagLib::ID3v2::TextIdentificationFrame("TPOS", TagLib::String::Latin1);
		NSAssert(NULL != frame, NSLocalizedStringFromTable(@"Unable to allocate memory.", @"Exceptions", @""));
		
		frame->setText(TagLib::String([[NSString stringWithFormat:@"/@u", [discTotal intValue]] UTF8String], TagLib::String::UTF8));
		f.tag()->addFrame(frame);
	}
	
	// Track length
	length = [metadata length];
	if(nil != [[self taskInfo] inputTracks]) {		
		// Sum up length of all tracks
		unsigned minutes	= [[[[self taskInfo] inputTracks] valueForKeyPath:@"@sum.minute"] unsignedIntValue];
		unsigned seconds	= [[[[self taskInfo] inputTracks] valueForKeyPath:@"@sum.second"] unsignedIntValue];
		unsigned frames		= [[[[self taskInfo] inputTracks] valueForKeyPath:@"@sum.frame"] unsignedIntValue];
		unsigned ms			= ((60 * minutes) + seconds + (unsigned)(frames / 75.0)) * 1000;
		
		frame = new TagLib::ID3v2::TextIdentificationFrame("TLEN", TagLib::String::Latin1);
		NSAssert(NULL != frame, NSLocalizedStringFromTable(@"Unable to allocate memory.", @"Exceptions", @""));
		
		frame->setText(TagLib::String([[NSString stringWithFormat:@"%u", ms] UTF8String], TagLib::String::UTF8));
		f.tag()->addFrame(frame);
	}
	else if(nil != length) {
		frame = new TagLib::ID3v2::TextIdentificationFrame("TLEN", TagLib::String::Latin1);
		NSAssert(NULL != frame, NSLocalizedStringFromTable(@"Unable to allocate memory.", @"Exceptions", @""));
		
		frame->setText(TagLib::String([[NSString stringWithFormat:@"%u", 1000 * [length intValue]] UTF8String], TagLib::String::UTF8));
		f.tag()->addFrame(frame);
	}
	
	// Album art
	albumArt = [metadata albumArt];
	if(nil != albumArt) {
		data			= getPNGDataForImage(albumArt); 
		pictureFrame	= new TagLib::ID3v2::AttachedPictureFrame();
		NSAssert(NULL != pictureFrame, NSLocalizedStringFromTable(@"Unable to allocate memory.", @"Exceptions", @""));
		
		pictureFrame->setMimeType(TagLib::String("image/png", TagLib::String::Latin1));
		pictureFrame->setPicture(TagLib::ByteVector((const char *)[data bytes], [data length]));
		f.tag()->addFrame(pictureFrame);
	}
	
	// MCN
	mcn = [metadata MCN];
	if (nil != mcn) {
		TagLib::ID3v2::UserTextIdentificationFrame *frame = new TagLib::ID3v2::UserTextIdentificationFrame(TagLib::String::Latin1);
		NSAssert(NULL != frame, @"Unable to allocate memory.");
		frame->setDescription("MCN");
		frame->setText(TagLib::String([mcn UTF8String], TagLib::String::UTF8));
		f.tag()->addFrame(frame);
	}
	
	// ISRC
	isrc = [metadata ISRC];
	if(nil != isrc) {
		frame = new TagLib::ID3v2::TextIdentificationFrame("TSRC", TagLib::String::Latin1);
		frame->setText(TagLib::String([isrc UTF8String], TagLib::String::UTF8));
		f.tag()->addFrame(frame);
	}
	
	// MusicBrainz Artist Id
	musicbrainzArtistId = [metadata musicbrainzArtistId];
	if (nil != musicbrainzArtistId) {
		TagLib::ID3v2::UserTextIdentificationFrame *frame = new TagLib::ID3v2::UserTextIdentificationFrame(TagLib::String::Latin1);
		NSAssert(NULL != frame, @"Unable to allocate memory.");
		frame->setDescription("MusicBrainz Artist Id");
		frame->setText(TagLib::String([musicbrainzArtistId UTF8String], TagLib::String::UTF8));
		f.tag()->addFrame(frame);
	}
	
	// MusicBrainz Album Id
	musicbrainzAlbumId = [metadata musicbrainzAlbumId];
	if (nil != musicbrainzAlbumId) {
		TagLib::ID3v2::UserTextIdentificationFrame *frame = new TagLib::ID3v2::UserTextIdentificationFrame(TagLib::String::Latin1);
		NSAssert(NULL != frame, @"Unable to allocate memory.");
		frame->setDescription("MusicBrainz Album Id");
		frame->setText(TagLib::String([musicbrainzAlbumId UTF8String], TagLib::String::UTF8));
		f.tag()->addFrame(frame);
	}
	
	// MusicBrainz Album Artist Id
	musicbrainzAlbumArtistId = [metadata musicbrainzAlbumArtistId];
	if (nil != musicbrainzAlbumArtistId) {
		TagLib::ID3v2::UserTextIdentificationFrame *frame = new TagLib::ID3v2::UserTextIdentificationFrame(TagLib::String::Latin1);
		NSAssert(NULL != frame, @"Unable to allocate memory.");
		frame->setDescription("MusicBrainz Album Artist Id");
		frame->setText(TagLib::String([musicbrainzAlbumArtistId UTF8String], TagLib::String::UTF8));
		f.tag()->addFrame(frame);
	}
	
	// MusicBrainz Disc Id
	musicbrainzDiscId = [metadata discId];
	if (nil != musicbrainzDiscId) {
		TagLib::ID3v2::UserTextIdentificationFrame *frame = new TagLib::ID3v2::UserTextIdentificationFrame(TagLib::String::Latin1);
		NSAssert(NULL != frame, @"Unable to allocate memory.");
		frame->setDescription("MusicBrainz Disc Id");
		frame->setText(TagLib::String([musicbrainzDiscId UTF8String], TagLib::String::UTF8));
		f.tag()->addFrame(frame);
	}
	
	// Unique file identifier
	musicbrainzTrackId = [metadata musicbrainzTrackId];
	if (nil != musicbrainzTrackId) {
		TagLib::ID3v2::UniqueFileIdentifierFrame *frame = new TagLib::ID3v2::UniqueFileIdentifierFrame(
																									   "http://musicbrainz.org", TagLib::ByteVector([musicbrainzTrackId UTF8String])
																									   );
		NSAssert(NULL != frame, @"Unable to allocate memory.");
		f.tag()->addFrame(frame);
	}
	
	// Encoded by
	frame = new TagLib::ID3v2::TextIdentificationFrame("TENC", TagLib::String::Latin1);
	NSAssert(NULL != frame, NSLocalizedStringFromTable(@"Unable to allocate memory.", @"Exceptions", @""));
	
	bundleVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
	versionString = [NSString stringWithFormat:@"Max %@", bundleVersion];
	frame->setText(TagLib::String([versionString UTF8String], TagLib::String::UTF8));
	f.tag()->addFrame(frame);
	
	// Encoding time
	frame = new TagLib::ID3v2::TextIdentificationFrame("TDEN", TagLib::String::Latin1);
	timestamp = getID3v2Timestamp();
	NSAssert(NULL != frame, NSLocalizedStringFromTable(@"Unable to allocate memory.", @"Exceptions", @""));
	
	frame->setText(TagLib::String([timestamp UTF8String], TagLib::String::UTF8));
	f.tag()->addFrame(frame);
	
	// Tagging time
	frame = new TagLib::ID3v2::TextIdentificationFrame("TDTG", TagLib::String::Latin1);
	timestamp = getID3v2Timestamp();
	NSAssert(NULL != frame, NSLocalizedStringFromTable(@"Unable to allocate memory.", @"Exceptions", @""));
	
	frame->setText(TagLib::String([timestamp UTF8String], TagLib::String::UTF8));
	f.tag()->addFrame(frame);
	
	f.save();
}

@end
