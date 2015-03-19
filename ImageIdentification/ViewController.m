//
//  ViewController.m
//  ImageIdentification
//
//  Created by 周俊杰 on 15/3/19.
//  Copyright (c) 2015年 北京金溪欣网络科技有限公司. All rights reserved.
//

#import "ViewController.h"
#import "ImageTargetsViewController.h"
@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)goScan {
    [self presentViewController:[[ImageTargetsViewController alloc] init] animated:YES completion:nil];
}

@end
