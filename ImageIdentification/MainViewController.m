//
//  MainViewController.m
//  ImageIdentification
//
//  Created by 周俊杰 on 15/3/23.
//  Copyright (c) 2015年 北京金溪欣网络科技有限公司. All rights reserved.
//

#import "MainViewController.h"
#import "ImageTargetsViewController.h"
@interface MainViewController ()

@end

@implementation MainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/
- (IBAction)goScan {
    [self.navigationController pushViewController:[[ImageTargetsViewController alloc] init] animated:YES];
}
@end
