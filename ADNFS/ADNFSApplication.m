//
//  ADNFSApplication.m
//  ADNFS
//
//  Created by Keitaroh Kobayashi on 4/14/14.
//  Copyright (c) 2014 Keitaroh Kobayashi. All rights reserved.
//

#import "ADNFSApplication.h"

#import <ADNKit/ADNKit.h>

static int adnfs_getattr(const char *path, struct stat *stbuf) {
    return [[ADNFSApplication sharedApplication] getAttrWithPath:path stat:stbuf];
}

static int adnfs_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                         off_t offset, struct fuse_file_info *fi) {
    
    return [[ADNFSApplication sharedApplication] readDirWithPath:path
                                                             buf:buf
                                                          filler:filler
                                                          offset:offset
                                                              fi:fi];
    
}

static int adnfs_open(const char *path, struct fuse_file_info *fi) {
    
    return [[ADNFSApplication sharedApplication] openPath:path
                                                       fi:fi];
    
}

static int adnfs_read(const char *path, char *buf, size_t size, off_t offset,
                      struct fuse_file_info *fi) {
    
    return [[ADNFSApplication sharedApplication] readPath:path
                                                      buf:buf
                                                     size:size
                                                   offset:offset
                                                       fi:fi];
}

@interface ADNFSApplication ()

@property (nonatomic, strong) ANKClient *client;

- (NSString *) nextFilenameForFilename:(NSString *) originalFilename;

@end

@implementation ADNFSApplication {
    /** Key: File ID, Object: ANKFile */
    NSMutableDictionary *_cachedFiles;

    /** Key: Filename, object: File ID */
    NSMutableDictionary *_sparseFileMap;
    
    dispatch_queue_t fuseQueue;
}

#pragma mark - Singleton

+ (instancetype) sharedApplication {
    static dispatch_once_t pred;
    static ADNFSApplication *shared = nil;
    
    dispatch_once(&pred, ^{
        shared = [[ADNFSApplication alloc] init];
    });
    
    return shared;
}

#pragma mark - FUSE methods

- (int) getAttrWithPath:(const char *)_path
                   stat:(struct stat *)stbuf
{
    int res = 0;
    
    memset(stbuf, 0, sizeof(struct stat));
    
    NSString *path = [NSString stringWithUTF8String:_path];
    NSArray *pathComponents = path.pathComponents;
    
    if (pathComponents.count == 1 && [pathComponents[0] isEqualToString:@"/"]) {
        // At root level.
        stbuf->st_mode = S_IFDIR | 0755;
        stbuf->st_nlink = 2;
    } else if (pathComponents.count == 2 && pathComponents[1]) {
        NSString *fileID = _sparseFileMap[pathComponents[1]];
        ANKFile *file = _cachedFiles[fileID];
        if (file) {
            stbuf->st_mode = S_IFREG | 0444;
            stbuf->st_nlink = 1;
            stbuf->st_size = file.sizeBytes;
            
            stbuf->st_mtime = stbuf->st_ctime = (long)file.createdAt.timeIntervalSince1970;
        } else {
            res = -ENOENT;
        }
    } else
        res = -ENOENT;
    
    return res;
}

- (int) readDirWithPath:(const char *)_path
                    buf:(void *) buf
                 filler:(fuse_fill_dir_t) filler
                 offset:(off_t) offset
                     fi:(struct fuse_file_info *)fi
{
    (void) offset;
	(void) fi;
    
    NSString *path = [NSString stringWithUTF8String:_path];
    
	if (![path isEqualToString:@"/"])
		return -ENOENT;
    
    filler(buf, ".", NULL, 0);
	filler(buf, "..", NULL, 0);
    
    for (NSString *filename in _sparseFileMap) {
        filler(buf, filename.UTF8String, NULL, 0);
    }
    
	return 0;
}

- (int) openPath:(const char *)_path
              fi:(struct fuse_file_info *)fi
{
    NSString *path = [NSString stringWithUTF8String:_path];
    
    if ((fi->flags & 3) != O_RDONLY)
        return -EACCES;
    
    return 0;
}

- (int) readPath:(const char *)path
             buf:(char *)buf
            size:(size_t)size
          offset:(off_t)offset
              fi:(struct fuse_file_info *)fi
{
    size_t len;
    (void) fi;
    
    // if(strcmp(path, hello_path) != 0)
    
    return -ENOENT;
    
    /*
    len = strlen(hello_str);
    if (offset < len) {
        if (offset + size > len)
            size = len - offset;
        memcpy(buf, hello_str + offset, size);
    } else
        size = 0;
    */
    
    return (int)size;
}

- (void) runWithArgc:(int) _argc
                argv:(char *[])_argv
{
    
    static struct fuse_operations adnfs_oper = {
        .getattr	= adnfs_getattr,
        .readdir	= adnfs_readdir,
        .open		= adnfs_open,
        .read		= adnfs_read,
    };

    int argc = _argc + 1;
    char ** argv = malloc(sizeof(char *) * argc);

    for (int i = 0; i <= _argc; i++) {
        int use = i;
        if (i == 0) {
            use--;
        }
        argv[use + 1] = _argv[i];
    }

    fuseQueue = dispatch_queue_create("us.kkob.FuseQueue", NULL);
    _cachedFiles = [NSMutableDictionary dictionary];
    _sparseFileMap = [NSMutableDictionary dictionary];
    
    // Let's take the opportunity to authenticate with ADN now.
    self.client = [[ANKClient alloc] init];
    
    NSString *accessToken = nil;
#ifdef MANUAL_ACCESS_TOKEN
    accessToken = MANUAL_ACCESS_TOKEN;
#endif
    
    [self.client logInWithAccessToken:accessToken
                           completion:
     ^(BOOL succeeded, ANKAPIResponseMeta *meta, NSError *error) {
         if (succeeded) {
             NSString *theMountpoint = [NSString stringWithFormat:@"/Volumes/@%@", self.client.authenticatedUser.username];
             char * mountpoint = malloc(sizeof(char) * (strlen(theMountpoint.UTF8String) + 1));

             strlcpy(mountpoint, theMountpoint.UTF8String, strlen(theMountpoint.UTF8String) + 1);

             mkdir(mountpoint, 0700);

             argv[1] = mountpoint;

             dispatch_async(fuseQueue, ^{
                 [self preloadAllFiles];
                 
                 NSLog(@"Mounting...");
                 fuse_main(argc, argv, &adnfs_oper, NULL);

                 free(mountpoint);
                 free(argv);

                 NSLog(@"FUSE is done!");
             });
         } else {
             NSLog(@"Hm. The access token was rejected: %@", error.description);
         }
     }];
}

#pragma mark - ADN methods

- (void) preloadAllFiles {
    ANKClient *currentClient =
    [self.client clientWithPagination:[ANKPaginationSettings settingsWithCount:200]];

    __block BOOL isMore = YES;
    
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    while (isMore) {
        [currentClient fetchCurrentUserFilesWithCompletion:
         ^(id responseObject, ANKAPIResponseMeta *meta, NSError *error) {
             NSArray *files = responseObject;
             for (ANKFile *file in files) {
                 _cachedFiles[file.fileID] = file;

                 NSString *newFilename = [self nextFilenameForFilename:file.name];
                 _sparseFileMap[newFilename] = file.fileID;
             }
             
             currentClient.pagination.beforeID = meta.minID;
             isMore = meta.moreDataAvailable;
             
             dispatch_semaphore_signal(semaphore);
         }];
        
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    }
}

- (NSString *) nextFilenameForFilename:(NSString *) originalFilename {
    if (![_sparseFileMap.allKeys containsObject:originalFilename]) {
        return originalFilename;
    }

    NSString *fileName = originalFilename;
    NSString *fileExtension = fileName.pathExtension;
    fileName = fileName.stringByDeletingPathExtension;

    static NSRegularExpression *regex = nil;

    if (!regex) {
        NSError *error = nil;

        regex =
        [NSRegularExpression regularExpressionWithPattern:@"-(\\d+)$"
                                                  options:NSRegularExpressionCaseInsensitive
                                                    error:&error];
    }

    NSTextCheckingResult *result =
    [regex firstMatchInString:fileName
                      options:0
                        range:NSMakeRange(0, fileName.length)];

    if (result) {

        NSString *oldNumber = [fileName substringWithRange:[result rangeAtIndex:1]];
        NSInteger theNumber = oldNumber.integerValue;
        theNumber ++;

        fileName = [fileName stringByReplacingCharactersInRange:result.range withString:[NSString stringWithFormat:@"-%ld", (long)theNumber]];

    } else {

        fileName = [fileName stringByAppendingString:@"-1"];

    }

    fileName = [fileName stringByAppendingPathExtension:fileExtension];

    return [self nextFilenameForFilename:fileName];
}

@end
