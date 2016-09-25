/*
 *  $Id: ApplicationController.h 1259 2007-10-14 05:15:10Z stephen_booth $
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

#import <Growl/GrowlApplicationBridge.h>

@interface NSApplication (ScriptingAdditions)
- (id) handleConvertScriptCommand:(NSScriptCommand *)command;
@end

@interface ApplicationController : NSObject <GrowlApplicationBridgeDelegate>
{
}

+ (ApplicationController *)		sharedController;

- (IBAction)			showPreferences:(id)sender;
- (IBAction)			showAcknowledgments:(id)sender;
- (IBAction)			showComponentVersions:(id)sender;

- (IBAction)			toggleRipperWindow:(id)sender;
- (IBAction)			toggleEncoderWindow:(id)sender;
- (IBAction)			toggleLogWindow:(id)sender;
- (IBAction)			toggleFormatsWindow:(id)sender;

- (IBAction)			openHomeURL:(id)sender;

- (IBAction)			encodeFile:(id)sender;

- (void)				encodeFiles:(NSArray *)filenames;

- (NSDictionary *)		registrationDictionaryForGrowl;

@end
