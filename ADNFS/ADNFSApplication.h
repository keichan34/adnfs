//
//  ADNFSApplication.h
//  ADNFS
//
//  Created by Keitaroh Kobayashi on 4/14/14.
//  Copyright (c) 2014 Keitaroh Kobayashi. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <fuse.h>

@class ANKClient;

@interface ADNFSApplication : NSObject

@property (nonatomic, strong, readonly) ANKClient *client;

+ (instancetype) sharedApplication;

- (void) runWithArgc:(int) argc argv:(char *[])argv;

- (int) getAttrWithPath:(const char *)path stat:(struct stat *)stbuf;
- (int) readDirWithPath:(const char *)path buf:(void *) buf filler:(fuse_fill_dir_t) filler offset:(off_t) offset fi:(struct fuse_file_info *)fi;
- (int) checkAccessPath:(const char *)path mask:(int) mask;
- (int) openPath:(const char *)path fi:(struct fuse_file_info *)fi;
- (int) readPath:(const char *)path buf:(char *) buf size:(size_t) size offset:(off_t) offset fi:(struct fuse_file_info *)fi;
- (int) statfs:(const char *)path stbuf:(struct statvfs *) stbuf;

@end
