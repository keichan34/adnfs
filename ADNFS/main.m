//
//  main.m
//  ADNFS
//
//  Created by Keitaroh Kobayashi on 4/14/14.
//  Copyright (c) 2014 Keitaroh Kobayashi. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "ADNFSApplication.h"

int main(int argc, const char * argv[])
{

    @autoreleasepool {
        ADNFSApplication *app = [ADNFSApplication sharedApplication];
        [app runWithArgc:argc argv:(char **)argv];
        
        dispatch_main();
    }
    
    return 0;
}
