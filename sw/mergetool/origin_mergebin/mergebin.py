#! /usr/bin/python3
# -*- coding: UTF-8 -*-

import sys
import re

'''
a tool for IP to build bsram init value fusemap
this script can read a special format data file and turn to bsram init value fusemap
this script has no CRC check function, so the output file could just used in fs file without CRC check

data file format:
e.g.
R36[1],R54[0],R36[2],R54[3],R36[3],R54[4],R45[6],R45[5]
11110000000000000000000000000000
11110000000000000000000000000000
00000000000000000000000000000000
00000000000000000000000000000000
00000000000000000000000000000000
00000000000000000000000000000000
00000000000000000000000000000000
...

the first line is bsram site declare, bsram declare num should the same as data colomn below
the data in the same colomn puts into a appointed bsram
if colomn number is more than bsram declare num, extra data'll be ignored
if colomn number is less than bsram declare num, code'll crash now
'''

CRC_POLYNOMIAL = 0x8005
CRC_TABLE = [0]*256

def reflect(ref, refLen):
    value=0
    for i in range(1,refLen+1):
        if ref&1:
            value=value|(1<<(refLen-i))
        ref >>= 1
    return value

def initCRCTab():
    tb_CRC16=[0]*256
    nData16=0
    nAccum16=0
    for nIdx in range(0,256):
        nData16=nIdx<<8
        nAccum16=0
        for nUm in range(0,8):
            if (nData16^nAccum16)&0x8000:
                nAccum16=(nAccum16<<1)^CRC_POLYNOMIAL
            else:
                nAccum16=nAccum16<<1
            nData16=nData16<<1
        tb_CRC16[nIdx]=nAccum16;
    for idx in range(0,0x100):
        CRC_TABLE[reflect(idx,8)]=reflect(tb_CRC16[idx],16)


def getCRC16_Byte(crcMsg):
    crc16=0
    for i in crcMsg:
        value = int(i)
        crc16=(((crc16>>8) | value<<8)^(CRC_TABLE[crc16&0x00FF]))
    for ix in range(0,2):
        crc16=((crc16>>8)^(CRC_TABLE[crc16&0x00FF]))
    return crc16

def generateInitMap(bitValList):
    bsramValTab=[22,23,28,29,31,32,36,38,39,40,
                     45,46,48,49,54,55,57,58,
                     62,63,65,66,71,72,73,74,80,
                     81,83,84,88,90,91,92,97,98,99,100,
                     106,107,108,110,114,115,117,118,
                     123,124,125,126,132,133,134,135,140,
                     141,143,144,149,150,151,152,157,158,160,
                     161,166,167,169,170,174,176]    
    bitValMap = [[0 for col in range(180)] for row in range(256)]
    usIdx=0
    while usIdx < len(bitValList):
        nWLOff = (usIdx>>6)&0x003F
        nWLGroup= (usIdx>>4)&0x0003
        nBLOff=(usIdx>>12)&0x0003
        if nWLGroup==1:
            nWLGroup =2
        elif nWLGroup==2:
            nWLGroup=1
        nWL = 64*nWLGroup+nWLOff
        for usIdxOff in range(0,8):
            if (bitValList[usIdx+usIdxOff]) == 1:
                nBL =4*usIdxOff + nBLOff
                nBitCol = bsramValTab[nBL]
                nBitCol=nBitCol-1
                (bitValMap[nWL])[nBitCol]=1
        usIdx= usIdx+8
        for  usIdxOff in range(0,8):
            if bitValList[usIdx+usIdxOff] == 1:
                nBL =4*(usIdxOff+9) +nBLOff
                nBitCol =bsramValTab[nBL]
                nBitCol=nBitCol-1
                (bitValMap[nWL])[nBitCol]=1
        usIdx=usIdx+8
    return bitValMap

class Device:
    def __init__(self, type):
        if(type == 'gw2a55'):
            self.row = 2038
            self.colomn = 5536
            self.bsramLineNum = [10,36,45,54,75]
            self.bsramLine = ['}phscemcemcemcemcemcemcemcemcemcemcemcemcemcemcemcemcemcemcemcemcemcemcemcemcemcemcemcem(_){',
                              'AphscemcemcemcemcemcemcemcemcemcemcemcemcemceHcemcemcemcemcemcemcemcemcemcemcemcemcemcem(_)a',
                              '#cemcemcemcemcemcemcemcemcemcemcemcemcemcemEFMNSVcemcemcemcemcemcemcemcemcemcemcemcemfgjknv!',
                              'AcemcemcemcemcemcemcemcemcemcemcemcemcemcemcePcemcemcemcemcemcemcemcemcemcemcemcemcemcemcema',
                              'AphscemcemcemcemcemcemcemcemcemcemcemcemcemceOcemcemcemcemcemcemcemcemcemcemcemcemcemcem(_)a']
        elif(type == 'gw2a18'):
            self.row = 1342
            self.colomn = 3376
            self.bsramLineNum = [10, 28, 46]
            self.bsramLine = ['}phscemcemcemcemcemcemcemcemcemcemcemcemcemcemcemcem(_){',
                              '#cemcemcemcemcemcemcemcemEFMNSVcemcemcemcemcemcemfgjknv!',
                              '}phscemcemcemcemcemcemcemcemcemcemcemcemcemcemcemcem(_){']

    def whichBsramLine(self, row):
        line = -1
        idx = 0
        while idx < len(self.bsramLineNum):
            if self.bsramLineNum[idx] == row:
                line = idx
                break
            idx = idx + 1
        return line

    def getFuseCol(self, lineIdx, index):
        fuseCol = -1;
        bsramLine = self.bsramLine[lineIdx]
        idx = 0
        while idx < len(bsramLine):
            if(bsramLine[idx] == 'c'):
                if index == 0:
                    fuseCol = idx
                    break
                else:
                    index = index - 1
            idx = idx + 1
        if index == 0:
            fuseCol = (fuseCol-1)*60 + 68
        return fuseCol

    def strToSite(self, strSite):
        fuseRow = -1
        fuseCol = -1
        site = re.split('[R\[\]]', strSite)
        site = list(filter(lambda x:x!='', site))
        lineIdx = self.whichBsramLine(int(site[0]))
        fuseRow = lineIdx*256 + 255
        fuseCol = self.getFuseCol(lineIdx, int(site[1]))
        return (fuseRow, fuseCol)
    
class initData:
    def __init__(self):
        self.siteMap = []
        self.dataMap = []
        self.bsramRow = 0
        self.bsramCol = 0        
        
    def __init__(self, strListSite, strListData):
        self.siteMap = []
        self.dataMap = []
        self.bsramRow = 0
        self.bsramCol = 0
        row = 0;
        while(row < len(strListSite)):
            self.siteMap.append(strListSite[row].split(','))
            row = row + 1
        self.bsramRow = len(self.siteMap)
        self.bsramCol = len(self.siteMap[0])
        self.analyzeBsramInitData(strListData)
    
    def analyzeBsramInitData(self, strListData):
        for row in range(len(self.siteMap)):
            oneLine = []
            for col in range(len(self.siteMap[row])):
                oneMap = [0 for index in range(256*64)]
                oneLine.append(oneMap)
            self.dataMap.append(oneLine)
        row = 0;
        col = 0;
        while(row < len(self.siteMap)):
            while(col < len(self.siteMap[row])):
                bitWidth = 0 if self.bsramCol==0 else 32/self.bsramCol
                rootRow = 16384*(row)
                rootCol = bitWidth*(col+1)-1
                bitRow = rootRow
                while(bitRow<len(strListData) and bitRow<rootRow+16384):
                    bitLine = strListData[bitRow]
                    offset = 0
                    while(offset < bitWidth):
                        if bitLine[int(rootCol - offset)] == '1':
                            index = int((bitRow-rootRow)*bitWidth + offset)
                            self.dataMap[row][col][index] = 1
                        offset = offset + 1
                    bitRow = bitRow + 1
                col = col + 1;
            row = row + 1;

def buildBsramInitValueFuseMap(binFile, siteFile, dev):
    print('Build bsram init value fusemap...')
    fusemap = [[0 for col in range(dev.colomn)] for row in range(len(dev.bsramLineNum)*256)]
    print('Location file ' + siteFile + ' reading...')
    infile = open(siteFile, 'r')
    siteArr = list(filter(None,infile.read().split('\n')))#infile.read().split('\n')
    dataArr = bin2txt(binFile)
    if(len(siteArr) > 0):
        newData = initData(siteArr, dataArr)
        for r in range(newData.bsramRow):
            for c in range(newData.bsramCol):
                (origRow, origCol) = dev.strToSite(newData.siteMap[r][c])
                bsramInitMap = generateInitMap(newData.dataMap[r][c])
                for mapR in range(len(bsramInitMap)):
                    for mapC in range(len(bsramInitMap[mapR])):
                        if bsramInitMap[mapR][mapC] == 1:
                            fusemap[origRow-mapR][origCol+mapC] = 1
                print('Bsram ' + newData.siteMap[r][c] + ' init value convert to fusemap success.')              
    else:
        print('Error: can not find bsram site information in ' + file)
    return fusemap

def initValBit2Byte(bitLine):
    byteLine = []
    idx = 7
    while idx < len(bitLine):
        byte = bitLine[idx-7]*128 + bitLine[idx-6]*64 + bitLine[idx-5]*32 + bitLine[idx-4]*16 + bitLine[idx-3]*8 + bitLine[idx-2]*4 + bitLine[idx-1]*2 + bitLine[idx]
        byteLine.append(byte)
        idx = idx + 8
    return byteLine

def checkDeviceType(fsFile):
    dev = 'gw2a55'
    print ('Read bit stream file ' + fsFile + ' ...')
    infile = open(fsFile,'r')
    content = infile.read()
    infile.close()
    lines = content.split('\n')
    idx = 0
    while idx < len(lines):
        line = lines[idx]
        if(len(line) == 64):
            if(line[0:8] == '00000110' or line[0:8] == '10000110'):
                if(line[8:] == '00000000000000000000000000001001000000000010100000011011'):
                    dev = 'gw1n1'
                elif(line[8:] == '00000000000000000000000000000000000000000010100000011011'):
                    dev = 'gw2a55'
                elif(line[8:] == '00000000000000000000000000000000000000000000100000011011'):
                    dev = 'gw2a18'
        elif(len(line) > 64):
            break;
        idx = idx + 1
    return dev 

def replaceBsramInitValueMap(fsFile, newMap, fuseLine):
    print('Replace new bsram init value map to file new_' + fsFile + '...')
    infile = open(fsFile,'r')
    content = infile.read()
    infile.close()
    lines = content.split('\n')
    outfile = open('new_' + fsFile,'w')
    checkCRC = False
    replaced = False
    idx = 0
    while idx < len(lines):
        line = lines[idx]
        if(len(line) <= 160):
            outfile.write(line+'\n')
            if(line[0:8] == '00111011'):
                checkCRC = True
                initCRCTab()
        else:
            if fuseLine > 0:
                outfile.write(line+'\n')
                fuseLine = fuseLine - 1
            elif replaced == False:
                replaced = True
                for line in newMap:
                    if(len(line)%8 != 0):
                        num = 8 - len(line)%8
                        while num != 0:
                            line.append(1)
                            num = num - 1
                    line.reverse()
                    for data in line:
                        outfile.write(str(data))
                    if checkCRC:
                        flag = [1]*48
                        byteLine = initValBit2Byte(flag + line)
                        CRC = getCRC16_Byte(byteLine)
                        outfile.write('{:0>8b}'.format(int(CRC%256)))
                        outfile.write('{:0>8b}'.format(int(CRC/256)))
                    outfile.write('111111111111111111111111111111111111111111111111\n')
        idx = idx + 1
    outfile.close()

def bin2txt(binFile):
    dataArr = []
    with open(binFile, 'rb') as f:
        binData = f.read()
    for i in range(len(binData)//4):
        if i < len(binData)//4:
            w = binData[4*i : 4*i+4]
            wp = w[0] + (w[1] << 8) + (w[2] << 16) + (w[3] << 24)
            s = bin(wp& int("1"*32, 2))[2:]
            dataArr.append(("{0:0>%s}" % (32)).format(s))
    return dataArr

if __name__ == '__main__':
    print("---------- My tool ----------")
    if(len(sys.argv) != 4):
        print('Error: illegal parameter.\nUsage: script <binary_data_file> <bsram_site_file> <fs_file>')    
    else:
        dev = Device(checkDeviceType(sys.argv[3]))
        bsramMap = buildBsramInitValueFuseMap(sys.argv[1], sys.argv[2], dev)
        replaceBsramInitValueMap(sys.argv[3], bsramMap, dev.row)
        print('Build bsram init value replace completed.')    
    
