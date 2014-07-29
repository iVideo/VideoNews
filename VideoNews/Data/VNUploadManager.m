//
//  VNUploadManager.m
//  VideoNews
//
//  Created by 曼瑜 朱 on 14-7-29.
//  Copyright (c) 2014年 Manyu Zhu. All rights reserved.
//

#import "VNUploadManager.h"
#import "AFNetworking.h"
#import "VNHTTPRequestManager.h"

#import "QiniuSimpleUploader.h"
#import "QiniuConfig.h"

//static Reachability *reach = nil;

@implementation VNUploadManager

#pragma mark - Upload

+(void)uploadImage:(NSData *)imageData Uid:(NSString *)uid completion:(void(^)(bool succeed,NSError *error))completion
{
    AFHTTPRequestOperationManager *manager = [AFHTTPRequestOperationManager manager];
    
    NSDictionary *parameters =@{@"key":[NSString stringWithFormat:@"thumbnail-%@.png",uid],@"uid":uid,@"token":[self LoginToken], @"timestamp": [self timestamp]};
    NSString *URLStr = [VNHost stringByAppendingString:@"qiniuToken.php"];
    [manager POST:URLStr parameters:parameters
          success:^(AFHTTPRequestOperation *operation,id responseObject) {
              //NSLog(@"Success: %@", responseObject);
              //获得签名信息
              if (responseObject && [responseObject isKindOfClass:[NSDictionary class]]&&[responseObject objectForKey:@"status"]) {
                  NSString *token=[responseObject objectForKey:@"Qtoken"];
                  QiniuSimpleUploader *sUploader=[QiniuSimpleUploader uploaderWithToken:token];
                  sUploader.delegate= self;
                  QiniuPutExtra *extra=[[QiniuPutExtra alloc]init];
                  extra.params= @{@"x:uid":uid};
                  kQiniuUpHosts[0]=@"http://upload.qiniu.com/";
                  [sUploader uploadFileData:imageData key:[NSString stringWithFormat:@"thumbnail-%@.png",uid] extra:extra];
              }
              if (completion) {
                  completion(YES, nil);
              }
          } failure:^(AFHTTPRequestOperation *operation,NSError *error) {
              //NSLog(@"%@",operation.request.URL.absoluteString);
              //NSLog(@"%@",operation);
              NSLog(@"Error: %@", error);
              if (completion) {
                  completion(NO, error);
              }
              
          }];
}
+ (NSString *)timestamp {
    //    NSLog(@"%@", [[self CCT_Date] description]);
    //    return [NSString stringWithFormat:@"%f", [[self CCT_Date] timeIntervalSince1970]];
    //http://zmysp.sinaapp.com/timestamp.php
    if ([VNHTTPRequestManager isReachable]) {
        NSString *URLStr = [VNHost stringByAppendingString:@"timestamp.php"];
        NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
        [request setURL:[NSURL URLWithString:URLStr]];
        [request setHTTPMethod:@"GET"];
        NSData *returnData = [NSURLConnection sendSynchronousRequest:request returningResponse:nil error:nil];
        NSError *error = nil;
        NSDictionary *responseObject = [NSJSONSerialization JSONObjectWithData:returnData options:kNilOptions error:&error];
        return [NSString stringWithFormat:@"%d", [[responseObject objectForKey:@"timestamp"] intValue]];
    }
    else {
        return [NSString stringWithFormat:@"%f", [[NSDate date] timeIntervalSince1970]];
    }
}

+ (NSString *)LoginToken {
    NSString *originTokenStr = [[NSString stringFromDate:[NSDate date]] stringByAppendingString:@"#$@%!*zmy"];
    //NSLog(@"%@", originTokenStr);
    return [originTokenStr md5];
}

// Upload completed successfully.
- (void)uploadSucceeded:(NSString *)filePath ret:(NSDictionary *)ret
{
    [self.delegate uploadSucceeded:filePath ret:ret];
}

// Upload failed.
- (void)uploadFailed:(NSString *)filePath error:(NSError *)error
{
    [self uploadFailed:filePath error:error];
}


@end