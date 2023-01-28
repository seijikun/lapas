#!/usr/bin/python3

import os;
import argparse;
import pathlib;
import shutil;
import re;

# ARG PARSING
#####################
parser = argparse.ArgumentParser(prog = 'keepEngine.py',
                    description = 'Keep Engine parses the base user\'s .keep file and deletes files accordingly',
                    epilog = 'LAPAS');
parser.add_argument('mode', choices=['base', 'user'], help="Mode of operation. Either applies the keep rules to ");
parser.add_argument('keepRulesFile', type=open, help="Path to the .keep file that should be applied");
parser.add_argument('folder', type=pathlib.Path, help="Folder that the rules should be applied to (either base user or normal user home)");
parser.add_argument('--dryrun', action='store_const', const=True, dest='dryrun', default=False, help="If this flag is set, the engine will run in test-mode");
args = parser.parse_args();

# PATTERNS
#####################
class Patterns:
        def __init__(self):
                # Full pattern that was specified in the .keep file
                self.mainPatterns = set();
                # All partial patterns generated from the full patterns in the .keep file
                # These are the single path components
                self.pathPatterns = set();

        def patternToRegex(pattern):
                pattern = pattern.replace('/**/', '/.*/');
                pattern = pattern.replace('/*/', '/[^/]+/');
                if(pattern.endswith('/*')):
                        pattern = pattern[0:-2] + '/[^/]+';
                pattern = pattern.replace('*', '[^/]*');
                pattern = "^" + pattern + "$";
                return re.compile(pattern);

        def addPattern(self, pattern):
                self.mainPatterns.add(Patterns.patternToRegex(pattern));
                pathSegments = pattern.split('/');
                partialPattern = '';
                for pathSegment in pathSegments:
                        if(partialPattern != ''):
                                partialPattern += '/';
                        partialPattern += pathSegment;
                        self.pathPatterns.add(Patterns.patternToRegex(partialPattern));


        def parseFromFile(keepFile):
                patternsBaseAlways = Patterns();
                patternsBaseInitially = Patterns();
                
                # default patterns
                patternsBaseAlways.addPattern('.keep');

                for line in keepFile.readlines():
                        if(line.startswith('b ')):
                                patternsBaseAlways.addPattern(line[2:].strip());
                        elif(line.startswith('bi ')):
                                patternsBaseInitially.addPattern(line[3:].strip());
                return (patternsBaseAlways, patternsBaseInitially);

        def anyRule(patterns, path):
                for pattern in patterns:
                        if(pattern.search(path) != None):
                                return True;
                return False;

        def anyMain(self, path):
                return Patterns.anyRule(self.mainPatterns, path);
        def anyPath(self, path):
                return Patterns.anyRule(self.pathPatterns, path);


# PATTERN ENGINE
#####################
class BasePatternEngine:
        def __init__(self, patternsBaseAlways, patternsBaseInitially):
                self.patternsBaseAlways = patternsBaseAlways;
                self.patternsBaseInitially = patternsBaseInitially;

        def shouldKeep(self, path):
                # keep if any subpath matches (we want/need to ascend it after all!)
                return self.patternsBaseAlways.anyPath(path) or self.patternsBaseInitially.anyPath(path) or self.patternsBaseAlways.anyMain(path) or self.patternsBaseInitially.anyMain(path);

        def shouldDescend(self, path):
                if(self.patternsBaseAlways.anyMain(path) or self.patternsBaseInitially.anyMain(path)):
                        return False; # Already accepted by main rule, no need to descend
                return self.patternsBaseAlways.anyPath(path) or self.patternsBaseInitially.anyPath(path);


class UserPatternEngine:
        def __init__(self, patternsBaseAlways):
                self.patternsBaseAlways = patternsBaseAlways;

        def shouldKeep(self, path):
                return not self.patternsBaseAlways.anyMain(path); # Delete if main pattern matches

        def shouldDescend(self, path):
                if(self.patternsBaseAlways.anyMain(path)):
                        return False; # Don't descend, already selected for deletion
                return self.patternsBaseAlways.anyPath(path);




def runCleanup(rootDir, curPath, patternEngine):
        curRelPath = os.path.relpath(curPath, start=rootDir);
        isCurPathFolder = os.path.isdir(curPath);

        if(curRelPath != '.'):
                # test self against patterns
                (shouldKeep, shouldDescend) = (patternEngine.shouldKeep(curRelPath), patternEngine.shouldDescend(curRelPath));
                if(not shouldKeep):
                        if isCurPathFolder:
                                if(args.dryrun):
                                        print("[Delete] folder: ", curRelPath);
                                else:
                                        shutil.rmtree(curPath);
                        else:
                                if(args.dryrun):
                                        print("[Delete] file: ", curRelPath);
                                else:
                                        os.remove(curPath);
                if(not isCurPathFolder or not shouldDescend):
                        return; # abort iteration

        if(isCurPathFolder): # if we are a folder, ascend deeper
                children = os.listdir(curPath);
                for childName in children:
                        childPath = os.path.join(curPath, childName);
                        runCleanup(rootDir, childPath, patternEngine);



if(os.path.isdir(args.folder) == False):
        print("The given folder does not exist!");
        exit();


(patternsBaseAlways, patternsBaseInitially) = Patterns.parseFromFile(args.keepRulesFile);
if(args.mode == 'base'):
        patternEngine = BasePatternEngine(patternsBaseAlways, patternsBaseInitially);
elif(args.mode == 'user'):
        patternEngine = UserPatternEngine(patternsBaseAlways);


if(args.mode == 'base'):
        runCleanup(args.folder, args.folder, patternEngine);
else:
        runCleanup(args.folder, args.folder, patternEngine);
