//  MyTableController.m
//  025-NSTableView
//
#import "WLTrackArticlePanel.h"
#import "WLGlobalConfig.h"
#import "WLConnection.h"
#import "WLTerminal.h"
#import "WLTrackDB.h"
#import "SynthesizeSingleton.h"
#import <CommonCrypto/CommonDigest.h>
#import <Crashlytics/Crashlytics.h>

@implementation NSString (TrimmingAdditions)

- (NSString *)stringByTrimmingLeadingCharactersInSet:(NSCharacterSet *)characterSet {
    NSUInteger location = 0;
    NSUInteger length = [self length];
    unichar charBuffer[length];
    [self getCharacters:charBuffer];
    
    for (location; location < length; location++) {
        if (![characterSet characterIsMember:charBuffer[location]]) {
            break;
        }
    }
    
    return [self substringWithRange:NSMakeRange(location, length - location)];
}

- (NSString *)stringByTrimmingTrailingCharactersInSet:(NSCharacterSet *)characterSet {
    NSUInteger location = 0;
    NSUInteger length = [self length];
    unichar charBuffer[length];
    [self getCharacters:charBuffer];
    
    for (length; length > 0; length--) {
        if (![characterSet characterIsMember:charBuffer[length - 1]]) {
            break;
        }
    }
    
    return [self substringWithRange:NSMakeRange(location, length - location)];
}

- (NSString *)MD5String {
    const char *cStr = [self UTF8String];
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5( cStr, (CC_LONG)strlen(cStr), result );
    
    return [NSString stringWithFormat:
            @"%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X",
            result[0], result[1], result[2], result[3],
            result[4], result[5], result[6], result[7],
            result[8], result[9], result[10], result[11],
            result[12], result[13], result[14], result[15]
            ];
}

@end


#define kTrackArticlePanelNibFilename @"WLTrackArticlePanel"
@implementation WLTrackArticlePanel
SYNTHESIZE_SINGLETON_FOR_CLASS(WLTrackArticlePanel);
@synthesize nsMutaryDataObj;
@synthesize idTableView;

- (void)awakeFromNib {
    [NSEvent addLocalMonitorForEventsMatchingMask:NSKeyUpMask handler:^NSEvent *(NSEvent *event) {
        NSWindow *targetWindow = event.window;
        if (targetWindow != articleWindow) {
            return event;
        }
        if ([event keyCode] == 53) {
            [self closeTrackArticleWindow:self];
        }
        if ([event keyCode] == 51 || [event keyCode] == 117) {
            [self removeArticleFromDB:self];
        }
        return event;
    }];
}

- (void)loadArticleFromDB: (NSString *)loginID {
    
    [[WLTrackDB sharedDBTools].queue inDatabase:^(FMDatabase *db) {
        NSUInteger count = [db intForQuery:[NSString stringWithFormat:@"SELECT COUNT(arID) FROM PttArticle WHERE owner='%@'", loginID]];
        if(count > 0) {
            FMResultSet *set = [db executeQuery:[NSString stringWithFormat:@"SELECT arID, owner, author, aid, board, title, url, lastLineHash, needTrack, astatus, datetime(ownTime, 'localtime') as ownTime FROM PttArticle WHERE owner='%@' ORDER BY astatus DESC", loginID]];
            self.nsMutaryDataObj = [[NSMutableArray alloc] init];
            
            while ([set next]) {
                NSInteger needTrack = [set intForColumn:@"needTrack"];
                NSInteger astatus = [set intForColumn:@"astatus"];
                NSString *board = [set stringForColumn:@"board"];
                NSString *author = [set stringForColumn:@"author"];
                NSString *title = [set stringForColumn:@"title"];
                NSString *url = [set stringForColumn:@"url"];
                NSString *aid = [set stringForColumn:@"aid"];
                NSString *lastLineHash = [set stringForColumn:@"lastLineHash"];
                NSString *ownTime = [set stringForColumn:@"ownTime"];
                
                WLArticle * zDataObject = [[[WLArticle alloc]initWithString1:board
                                                                  andString2:title
                                                                  andString3:url
                                                                  andString4:aid
                                                                  andString5:ownTime
                                                                  andString6:lastLineHash
                                                                  andString7:author
                                                                  andString8:(int)needTrack
                                                                  andString9:(int)astatus] autorelease];
                [self.nsMutaryDataObj addObject:zDataObject];
                
            }
            [set close];
        } else {
            self.nsMutaryDataObj = [[NSMutableArray alloc] init];
        }
    }];
}

- (NSString *)getTerminalBottomLine:(WLTerminal *) terminal {
    const int linesPerPage = [[WLGlobalConfig sharedInstance] row] - 1;
    return [terminal stringAtIndex:linesPerPage * [[WLGlobalConfig sharedInstance] column] length:[[WLGlobalConfig sharedInstance] column]] ?: @"";
}

- (void) showMsgOnMainWindow:(NSString *) msg {
    NSBeginAlertSheet(NSLocalizedString(@"Article Tracking", @"Sheet Title"),
                      NSLocalizedString(@"Confirm", @"Default Button"),
                      nil,
                      nil,
                      mainWindow, self,
                      //@selector(confirmSheetDidEnd:returnCode:contextInfo:),
                      nil,
                      nil,
                      nil,
                      NSLocalizedString(msg, @"Sheet Message"));
}

- (void) showMsgOnArticleWindow:(NSString *) msg {
    NSBeginAlertSheet(NSLocalizedString(@"Article Tracking", @"Sheet Title"),
                      NSLocalizedString(@"Confirm", @"Default Button"),
                      nil,
                      nil,
                      articleWindow, self,
                      //@selector(confirmSheetDidEnd:returnCode:contextInfo:),
                      nil,
                      nil,
                      nil,
                      NSLocalizedString(msg, @"Sheet Message"));
}

- (void)getArticleDetail:(WLTerminal *) terminal {
    int i=0;
    const int sleepTime = 100000, maxAttempt = 80;
    NSString *owner, *author, *aid, *board, *title, *url, *lastLineHash, *bottomLine, *tmp;
    BOOL changePageStatus;
    WLConnection *conn = [terminal connection];
    
    // 1 step, go to 1st page of the selected article
    if([[self getTerminalBottomLine:terminal] containsString:@"目前顯示: 第"]){
        [conn sendText:termKeyHome];
        while(i< maxAttempt) {
            // wait for the screen to refresh
            ++i;
            usleep(sleepTime);
            bottomLine = [self getTerminalBottomLine:terminal];
            if([bottomLine containsString:@"目前顯示: 第 01~"]){
                changePageStatus = YES;
                i = 0;
                break;
            } else {
                changePageStatus = NO;
            }
        }
        if(!changePageStatus) {
            //show warn
            [self performSelectorOnMainThread:@selector(showMsgOnMainWindow:) withObject:@"Something goes wrong while retrieving article details (1)" waitUntilDone:NO];
            return;
        }
    } else if ([[self getTerminalBottomLine:terminal] containsString:@"文章選讀"]) {
        // send "enter" to get to 1st page of article
        [conn sendBytes:"\r" length:1];
        while(i< maxAttempt) {
            // wait for the screen to refresh
            ++i;
            usleep(sleepTime);
            bottomLine = [self getTerminalBottomLine:terminal];
            if([bottomLine containsString:@"目前顯示: 第 01~"]){
                changePageStatus = YES;
                i = 0;
                break;
            } else {
                changePageStatus = NO;
            }
        }
        if(!changePageStatus) {
            //show warn
            [self performSelectorOnMainThread:@selector(showMsgOnMainWindow:) withObject:@"Something goes wrong while retrieving article details (2)" waitUntilDone:NO];
            return;
        }
    }
    
    // 2nd step: retrieve author/title/board from 1st page
    tmp = [self getTerminalNthLine:1 forTerminal: terminal];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"作者[: ]+([a-zA-Z0-9]{2,12}).+看板[ ]+([a-zA-Z0-9_\\-]+)" options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:tmp options:NSAnchoredSearch range:NSMakeRange(0, tmp.length)];
    author = [tmp substringWithRange:[match rangeAtIndex: 1]];
    board = [tmp substringWithRange:[match rangeAtIndex: 2]];
    
    tmp = [self getTerminalNthLine:2 forTerminal: terminal];
    regex = [NSRegularExpression regularExpressionWithPattern:@"標題[: ](.+)" options:0 error:nil];
    match = [regex firstMatchInString:tmp options:NSAnchoredSearch range:NSMakeRange(0, tmp.length)];
    NSRange needleRange = [match rangeAtIndex: 1];
    title = [[tmp substringWithRange:needleRange] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    title = [title stringByReplacingOccurrencesOfString:@"'" withString:@"''"];
    
    // 3rd step: retrieve aid/url/lastLineHash
    // lastLineHash first
    [conn sendBytes:"$" length:1];
    while(i< maxAttempt) {
        // wait for the screen to refresh
        ++i;
        usleep(sleepTime);
        bottomLine = [self getTerminalBottomLine:terminal];
        if([bottomLine containsString:@"頁 (100%)  目前顯示: 第"]){
            changePageStatus = YES;
            i = 0;
            break;
        } else {
            changePageStatus = NO;
        }
    }
    if(!changePageStatus) {
        //show warn
        [self performSelectorOnMainThread:@selector(showMsgOnMainWindow:) withObject:@"Something goes wrong while retrieving article details (3)" waitUntilDone:NO];
        return;
    }
    
    // now detect the last comment line number
    cell **_grid = [terminal grid];
    int lastLine = 0;
    for(i=0; i< [terminal maxRow]-1; ++i) {
        if(_grid[i][75].byte == ':' && (
                                        (_grid[i][0].byte == 0xA1 && _grid[i][1].byte == 0xF7) ||
                                        (_grid[i][0].byte == 0xB1 && _grid[i][1].byte == 0xC0) ||
                                        (_grid[i][0].byte == 0xBC && _grid[i][1].byte == 0x4E) )
           ){
            lastLine = i;
        }
    }
    if(!lastLine) {
        lastLineHash = @"";
    } else {
        lastLineHash = [[self getTerminalNthLine:(lastLine+1) forTerminal: terminal] MD5String];
        
        tmp = [self getTerminalNthLine:(lastLine+1) forTerminal: terminal];
        regex = [NSRegularExpression regularExpressionWithPattern:@"^([推噓→]) (\\w{2,12}.+?): (.+) ((?:\\d{1,3}\\.){3}\\d{1,3})? (\\d\\d/\\d\\d \\d\\d:\\d\\d)" options:NSRegularExpressionSearch error:nil];
        NSTextCheckingResult *result = [regex firstMatchInString:tmp options:0 range:NSMakeRange(0, [tmp length] ) ];
        //match = [regex firstMatchInString:tmp options:NSAnchoredSearch range:NSMakeRange(0, tmp.length)];
        
        if (result) {
            NSRange group1 = [result rangeAtIndex:1]; // push or dislike
            NSRange group2 = [result rangeAtIndex:2]; // user id withspace
            NSRange group3 = [result rangeAtIndex:3]; // comment with space
            NSRange group4 = [result rangeAtIndex:4]; // user ip (if required by board)
            NSRange group5 = [result rangeAtIndex:5]; // comment date
            
            NSString *combinedString;
            if(group4.length > 0){
                combinedString = [NSString stringWithFormat:@"%@%@%@%@ %@", [tmp substringWithRange:group1], [[tmp substringWithRange:group2] stringByTrimmingTrailingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]], [[tmp substringWithRange:group3] stringByTrimmingTrailingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]], [tmp substringWithRange:group4], [tmp substringWithRange:group5]];
            } else {
                combinedString = [NSString stringWithFormat:@"%@%@%@%@", [tmp substringWithRange:group1], [[tmp substringWithRange:group2] stringByTrimmingTrailingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]], [[tmp substringWithRange:group3] stringByTrimmingTrailingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]], [tmp substringWithRange:group5]];
            }
            lastLineHash = [combinedString MD5String];
        } else {
            lastLineHash = @"";
        }
    }
    
    // get AID/URL
    i = 0;
    [conn sendBytes:"Q" length:1];
    while(i< maxAttempt) {
        // wait for the screen to refresh
        ++i;
        usleep(sleepTime);
        bottomLine = [self getTerminalBottomLine:terminal];
        if([bottomLine containsString:@"請按任意鍵繼續"]){
            changePageStatus = YES;
            i = 0;
            break;
        } else {
            changePageStatus = NO;
        }
    }
    if(!changePageStatus) {
        //show warn
        [self performSelectorOnMainThread:@selector(showMsgOnMainWindow:) withObject:@"Something goes wrong while retrieving article details (4)" waitUntilDone:NO];
        return;
    }
    
    tmp = [self getTerminalNthLine:20 forTerminal: terminal];
    regex = [NSRegularExpression regularExpressionWithPattern:@"文章代碼\\(AID\\): ([a-zA-Z0-9#\-_]{9})" options:0 error:nil];
    match = [regex firstMatchInString:tmp options:NSAnchoredSearch range:NSMakeRange(0, tmp.length)];
    needleRange = [match rangeAtIndex: 1];
    aid = [tmp substringWithRange:needleRange];
    
    tmp = [self getTerminalNthLine:21 forTerminal: terminal];
    regex = [NSRegularExpression regularExpressionWithPattern:@"文章網址: https://www.ptt.cc/bbs/(.+)\\.html" options:0 error:nil];
    match = [regex firstMatchInString:tmp options:NSAnchoredSearch range:NSMakeRange(0, tmp.length)];
    needleRange = [match rangeAtIndex: 1];
    url = [tmp substringWithRange:needleRange];
    
    // send final enter to restore terminal
    [conn sendBytes:"\r" length:1];
    
    if( [author length] == 0 || [aid length] == 0 || [board length] == 0 || [title length] == 0 || [url length] ==0) {
        // show warn
        NSLog(@"author: %@, aid: %@, board: %@, title: %@, url: %@", author, aid, board, title, url);
        [self performSelectorOnMainThread:@selector(showMsgOnMainWindow:) withObject:@"Something goes wrong while retrieving article details (5)" waitUntilDone:NO];
        return;
    } else {
        // check if already in db
        __block BOOL alreadyInDB = NO;
        [[WLTrackDB sharedDBTools].queue inDatabase:^(FMDatabase *db) {
            NSString *owner = [[self.terminal connection] loginID];
            NSString *sql = [NSString stringWithFormat:@"SELECT COUNT(arID) FROM PttArticle WHERE board='%@' AND aid='%@' AND owner='%@'", board, aid, owner];
            NSUInteger count = [db intForQuery:sql];
            if(count > 0) {
                alreadyInDB = YES;
            }
        }];
        
        if(!alreadyInDB){
            // add to db and show good
            owner = [[terminal connection] loginID];
            [[WLTrackDB sharedDBTools].queue inDatabase:^(FMDatabase *db) {
                [db beginTransaction];
                NSString *sql = [NSString stringWithFormat:@"INSERT INTO PttArticle(owner, author, aid, board, title, url, lastLineHash, needTrack, astatus) VALUES ('%@','%@','%@','%@','%@','%@','%@', '%d', '%d')", owner, author, aid, board, title, url, lastLineHash, 0, 0];
                
                [db executeUpdate: sql];
                [db commit];
                [self performSelectorOnMainThread:@selector(showMsgOnMainWindow:) withObject:@"The articles has been stored successfully!" waitUntilDone:NO];
            }];
        } else {
            [self performSelectorOnMainThread:@selector(showMsgOnMainWindow:) withObject:@"This article is already in database!" waitUntilDone:NO];
        }
    }
}

- (NSString *)getTerminalNthLine:(int) i forTerminal:(WLTerminal *) terminal{
    const int line = i - 1;
    return [terminal stringAtIndex:line * [[WLGlobalConfig sharedInstance] column] length:[[WLGlobalConfig sharedInstance] column]] ?: @"";
}

- (void)addTrackArticle:(NSWindow *) window forTerminal:(WLTerminal *) terminal {
    if(![[terminal connection] isPTT] && (![[self getTerminalBottomLine:terminal] containsString:@"文章選讀"] || ![[self getTerminalBottomLine:terminal] containsString:@"目前顯示: 第"])){
        //show warn
        [self performSelectorOnMainThread:@selector(showMsgOnMainWindow:) withObject:@"Please make sure you're reading article in PTT" waitUntilDone:NO];
    } else {
        [NSThread detachNewThreadSelector:@selector(getArticleDetail:)
                                 toTarget:self
                               withObject:terminal];
    }
}

- (IBAction)removeArticleFromDB:(id)sender {
    NSIndexSet *indexSet = [idTableView selectedRowIndexes];
    
    if([indexSet count] > 0){
        NSAlert *alert = [[NSAlert alloc] init];
        [alert addButtonWithTitle:NSLocalizedString(@"Confirm", @"Default Button")];
        [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"Cancel Button")];
        [alert setMessageText:NSLocalizedString(@"Are your sure you want to delete selected articles from database?", @"Sheet Title")];
        [alert setInformativeText:NSLocalizedString(@"Deleted records cannot be restored.", @"Sheet Message")];
        [alert setAlertStyle:NSWarningAlertStyle];
        
        if ([alert runModal] != NSAlertFirstButtonReturn) {
            [alert release];
            return;
        }
        [alert release];
        
        // remove from db
        NSUInteger index=[indexSet firstIndex];
        while(index != NSNotFound) {
            
            WLArticle *article = self.nsMutaryDataObj[index];
            [[WLTrackDB sharedDBTools].queue inDatabase:^(FMDatabase *db) {
                NSString *owner = [[self.terminal connection] loginID];
                [db beginTransaction];
                NSString *sql = [NSString stringWithFormat:@"DELETE FROM PttArticle WHERE owner='%@' AND aid='%@' AND board='%@'", owner, article.aid, article.board];
                [db executeUpdate: sql];
                [db commit];
            }];
            index=[indexSet indexGreaterThanIndex: index];
        }
        [self.nsMutaryDataObj removeObjectsAtIndexes:indexSet];
        [idTableView reloadData];
    }
    
    
}

- (void)enterBoard:(WLArticle *) article {
    const int sleepTime = 100000, maxAttempt = 80;
    int i=0;
    NSString *bottomLine;
    BOOL changePageStatus=NO;
    WLConnection *conn = [self.terminal connection];
    
    // go to the board
    [conn sendText:[NSString stringWithFormat:@"s%@\r", article.board]];
    while(i< maxAttempt) {
        // wait for the screen to refresh
        ++i;
        usleep(sleepTime);
        bottomLine = [self getTerminalBottomLine:self.terminal];
        if([bottomLine containsString:@" 文章選讀 "]){
            changePageStatus = YES;
            i = 0;
            break;
        } else if([bottomLine containsString:@"請按任意鍵繼續"] || [bottomLine containsString:@"進入已知板名"]) {
            usleep(sleepTime);
            [conn sendBytes:"\r" length:1];
            usleep(sleepTime);
        }else {
            changePageStatus = NO;
        }
    }
    if(!changePageStatus) {
        //show warn
        [self performSelectorOnMainThread:@selector(showMsgOnArticleWindow:) withObject:@"Something goes wrong while navigating to stored article (1)" waitUntilDone:NO];
        return;
    }
    
    // move to aid
    [conn sendText:[NSString stringWithFormat:@"%@\r\r", article.aid]];
    while(i< maxAttempt) {
        // wait for the screen to refresh
        ++i;
        usleep(sleepTime);
        bottomLine = [self getTerminalBottomLine:self.terminal];
        if([bottomLine containsString:@"目前顯示: 第"]){
            changePageStatus = YES;
            i = 0;
            break;
        } else {
            changePageStatus = NO;
        }
    }
    if(!changePageStatus) {
        //show warn
        [self performSelectorOnMainThread:@selector(showMsgOnArticleWindow:) withObject:@"Something goes wrong while navigating to stored article (2)" waitUntilDone:NO];
        return;
    } else {
        // successfully enter the board by double-clicking so we can clear article status to 0
        // move to the end of the article
        [conn sendBytes:"$" length:1];
        
        [self performSelectorOnMainThread:@selector(clearArticleStatus:) withObject:article waitUntilDone:YES];
        [self performSelectorOnMainThread:@selector(closeTrackArticleWindow:) withObject:[NSObject new] waitUntilDone:NO];
    }
    
    
}

- (void)clearArticleStatus:(WLArticle *) article {
    NSString *owner = [[self.terminal connection] loginID];
    [[WLTrackDB sharedDBTools].queue inDatabase:^(FMDatabase *db) {
        NSString *owner = [[self.terminal connection] loginID];
        [db beginTransaction];
        NSString *sql = [NSString stringWithFormat:@"UPDATE PttArticle SET astatus='%d' WHERE board='%@' AND aid='%@' AND owner='%@'",0, article.board, article.aid, owner];
        [db executeUpdate: sql];
        [db commit];
    }];
}

- (void)doubleClick:(id)sender {
    if([[self.terminal connection] isConnected]) {
        NSInteger rowNumber = [idTableView clickedRow];
        if (rowNumber < 0) // double click on header, just ignore it
            return;
        WLArticle *article = self.nsMutaryDataObj[rowNumber];
        [NSThread detachNewThreadSelector:@selector(enterBoard:)
                                 toTarget:self
                               withObject:article];
    }
}

- (void)openTrackArticleWindow:(NSWindow *)window forTerminal:(WLTerminal *)terminal {
    if(![[terminal connection] isPTT] || ![[terminal connection] isConnected] || ![[[terminal connection] loginID] isKindOfClass:[NSString class]]){
        //show warn
        [self performSelectorOnMainThread:@selector(showMsgOnMainWindow:) withObject:@"Please make sure you're reading article in PTT" waitUntilDone:NO];
        return;
    } else if([[[terminal connection] loginID] isEqualToString:@""]) {
        [self performSelectorOnMainThread:@selector(showMsgOnMainWindow:) withObject:@"You MUST connect PTT with correct format!!" waitUntilDone:NO];
        return;
    }
    if (!articleWindow) {
        [NSBundle loadNibNamed:kTrackArticlePanelNibFilename owner:self];
    }
    
    [self loadArticleFromDB:[[terminal connection] loginID]];
    self.terminal = terminal;
    self.mainWindow = window;
    
    [idTableView reloadData];
    [idTableView setAllowsMultipleSelection: YES];
    [idTableView setTarget:self];
    [idTableView setDoubleAction:@selector(doubleClick:)];
    
    // setting up column sorting
    NSTableColumn *AuthorColumn = [idTableView tableColumnWithIdentifier:@"Col_ID1"];
    NSSortDescriptor *AuthorSortDescriptor = [NSSortDescriptor
                                              sortDescriptorWithKey:@"author"
                                              ascending:YES
                                              selector:@selector(caseInsensitiveCompare:)];
    [AuthorColumn setSortDescriptorPrototype:AuthorSortDescriptor];
    
    NSTableColumn *BoardColumn = [idTableView tableColumnWithIdentifier:@"Col_ID2"];
    NSSortDescriptor *BoardSortDescriptor = [NSSortDescriptor
                                             sortDescriptorWithKey:@"board"
                                             ascending:YES
                                             selector:@selector(caseInsensitiveCompare:)];
    [BoardColumn setSortDescriptorPrototype:BoardSortDescriptor];
    
    NSTableColumn *ownTimeColumn = [idTableView tableColumnWithIdentifier:@"Col_ID4"];
    NSSortDescriptor *ownTimeSortDescriptor = [NSSortDescriptor
                                               sortDescriptorWithKey:@"ownTime"
                                               ascending:YES
                                               selector:@selector(compare:)];
    [ownTimeColumn setSortDescriptorPrototype:ownTimeSortDescriptor];
    
    NSTableColumn *needTrackColumn = [idTableView tableColumnWithIdentifier:@"Col_ID5"];
    NSSortDescriptor *needTrackSortDescriptor = [NSSortDescriptor
                                                 sortDescriptorWithKey:@"needTrack"
                                                 ascending:YES
                                                 selector:@selector(compare:)];
    [needTrackColumn setSortDescriptorPrototype:needTrackSortDescriptor];
    
    [NSApp beginSheet:articleWindow
       modalForWindow:window
        modalDelegate:nil
       didEndSelector:NULL
          contextInfo:nil];
    
}

- (void)tableView:(NSTableView *)aTableView sortDescriptorsDidChange:(NSArray *)oldDescriptors
{
    [self.nsMutaryDataObj sortUsingDescriptors:[idTableView sortDescriptors]];
    [idTableView reloadData];
}

- (IBAction)deleteSelectedRow:(id)pId {
    if ([idTableView selectedRow] > -1) {
        [self.nsMutaryDataObj removeObjectAtIndex:[idTableView selectedRow]];
        [idTableView reloadData];
    } // end if
} // end deleteSelectedRow

- (IBAction)closeTrackArticleWindow:(id)sender {
    [articleWindow endEditingFor:nil];
    [NSApp endSheet:articleWindow];
    [articleWindow orderOut:self];
    //[[self nsMutaryDataObj] removeAllObjects];
    [self release];
}

- (int)numberOfRowsInTableView:(NSTableView *)pTableViewObj {
    return [self.nsMutaryDataObj count];
} // end numberOfRowsInTableView


- (id) tableView:(NSTableView *)pTableViewObj objectValueForTableColumn:(NSTableColumn *)pTableColumn row:(int)pRowIndex {
    WLArticle * zDataObject = (WLArticle *) [self.nsMutaryDataObj objectAtIndex:pRowIndex];
    
    if (! zDataObject) {
        NSLog(@"tableView: objectAtIndex:%d = NULL",pRowIndex);
        return NULL;
    } // end if
    
    if ([[pTableColumn identifier] isEqualToString:@"Col_ID1"]) {
        return [zDataObject author];
    }
    
    if ([[pTableColumn identifier] isEqualToString:@"Col_ID2"]) {
        return [zDataObject board];
    }
    
    if ([[pTableColumn identifier] isEqualToString:@"Col_ID3"]) {
        return [zDataObject title];
    }
    
    if ([[pTableColumn identifier] isEqualToString:@"Col_ID4"]) {
        return [zDataObject ownTime];
    }
    
    if ([[pTableColumn identifier] isEqualToString:@"Col_ID5"]) {
        return [NSNumber numberWithBool:[zDataObject needTrack]];
    }
    
    NSLog(@"***ERROR** dropped through pTableColumn identifiers");
    return NULL;
    
}

- (void)tableView:(NSTableView *)pTableViewObj setObjectValue:(id)pObject forTableColumn:(NSTableColumn *)pTableColumn row:(int)pRowIndex {
    WLArticle *article = [self.nsMutaryDataObj objectAtIndex:pRowIndex];
    
    if([[pTableColumn identifier] isEqualToString:@"Col_ID5"]){
        article.needTrack = [pObject boolValue] ? 1 : 0;
        
        //update db
        [[WLTrackDB sharedDBTools].queue inDatabase:^(FMDatabase *db) {
            NSString *owner = [[self.terminal connection] loginID];
            [db beginTransaction];
            NSString *sql = [NSString stringWithFormat:@"UPDATE PttArticle SET needTrack='%d' WHERE board='%@' AND aid='%@' AND owner='%@'",([pObject boolValue] ? 1 : 0), article.board, article.aid, owner];
            [db executeUpdate: sql];
            [db commit];
        }];
    }
}

- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSColor *newCommentColor = [NSColor colorWithCalibratedRed:0.623529 green:0.835294 blue:0.631372 alpha:1.0f];
    WLArticle *article = self.nsMutaryDataObj[row];
    
    [cell setDrawsBackground:YES];
    if(article.astatus == 1){
        [cell setBackgroundColor:newCommentColor];
    } else if (article.astatus == 2) {
        [cell setBackgroundColor:[NSColor redColor]];
    } else {
        [cell setBackgroundColor:[NSColor whiteColor]];
    }
}


@end
