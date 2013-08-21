//
//  Header.h
//  Unichapel
//
//  Created by Jon Como on 10/18/12.
//  Copyright (c) 2012 Jon Como. All rights reserved.
//

#ifndef Unichapel_Header_h
#define Unichapel_Header_h

#define DOCUMENTS [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0]
#define DELEGATE [[UIApplication sharedApplication] delegate]
#define NOTIFICATION [NSNotificationCenter defaultCenter]
#define FILEMANAGER [NSFileManager defaultManager]
#define DEFAULTS [NSUserDefaults standardUserDefaults]
#define IS_iPAD [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad

#endif