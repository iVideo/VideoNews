//
//  VNCustomizedAlbumPickerController.m
//  VideoNews
//
//  Created by zhangxue on 14-7-21.
//  Copyright (c) 2014年 Manyu Zhu. All rights reserved.
//

#import "VNCustomizedAlbumPickerController.h"
#import <AVFoundation/AVFoundation.h>
#import "VNAlbumVideoEditController.h"

@interface VNCustomizedAlbumPickerController ()<UINavigationControllerDelegate, UIImagePickerControllerDelegate>

@end

@implementation VNCustomizedAlbumPickerController

- (id)init
{
    self = [super init];
    if (self) {
        
        self.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        self.mediaTypes = @[@"public.movie"];
        self.delegate = self;
        
        BOOL _isDir;
        NSString *fileDir = [VNUtility getNSCachePath:@"VideoFiles"];
        
        if(![[NSFileManager defaultManager] fileExistsAtPath:fileDir isDirectory:&_isDir]){
            if (![[NSFileManager defaultManager] createDirectoryAtPath:fileDir withIntermediateDirectories:YES attributes:nil error:nil]) {
                
            }
        }
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];

}

#pragma mark UIImagePickerControllerDelegate

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
{
    NSString *mediaType = [info objectForKey:UIImagePickerControllerMediaType];
    
    NSLog(@"info....:%@",info);
    
    if ([mediaType isEqualToString:@"public.movie"] && picker.sourceType == UIImagePickerControllerSourceTypePhotoLibrary){
        
        NSURL *videoURL = [info objectForKey:UIImagePickerControllerMediaURL];
        AVAsset *anAsset = [[AVURLAsset alloc] initWithURL:videoURL options:nil];
        float currVideoDuration = anAsset.duration.value / anAsset.duration.timescale;
        
        if (currVideoDuration < 5.0) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"亲~~视频时长至少要5秒哦~~" message:nil delegate:self cancelButtonTitle:@"确定" otherButtonTitles:nil];
            [alert show];
            [self popViewControllerAnimated:YES];
        }else {
            __weak VNCustomizedAlbumPickerController *weakSelf = self;
            NSString *videoPath = [VNUtility getNSCachePath:@"VideoFiles"];
            
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSData *videoData = [NSData dataWithContentsOfURL:videoURL];
                
                NSString *filePath = [videoPath stringByAppendingPathComponent:@"VN_Video_Final.mov"];
                if ([videoData writeToFile:filePath atomically:YES]) {
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        NSLog(@"filePath: %@",filePath);
                        VNAlbumVideoEditController *editCtl = [[VNAlbumVideoEditController alloc] initWithVideoPath:filePath];
                        [weakSelf pushViewController:editCtl animated:YES];
                    });
                }
            });
            
        }
    }
    
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end