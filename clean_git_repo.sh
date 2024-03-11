#!/bin/bash

# 可以清除的文件名后缀列表
DELETABLE_SUFFIXS=("exe" "gz" "tar" "jar" "tmp" "temp" "log" "swp" "um" "class" "out")
# 可以清除的文件名结尾字符
DELETABLE_SUFFIXW=("~" "!")
# 可以清除的文件大小最小限制，默认 1mb(1024 * 1024b), 可以改成 0，则完全以文件名为准进行清理
DELTEABLE_FILE_MIN=1048576


CURR_DIR=$(pwd)
WORK_DIR=$1
TEST=$2


# 判断传入的目录是否为 git仓库目录
function isGitDir() {
	if [[ $WORK_DIR =~ ^\.\/* ]]; then 
		WORK_DIR=${WORK_DIR#\.\/}
	fi

	if [[ ! $WORK_DIR =~ ^\/.* ]]; then
		WORK_DIR=$PWD"/"$WORK_DIR
	fi
	
	if [[ ! $WORK_DIR =~ \/$ ]]; then
		WORK_DIR=$WORK_DIR"/"
	fi
	
	if [ ! -d $WORK_DIR ]; then
		echo "工作路径 $WORK_DIR 不是一个文件夹！"
		help
		exit -1
	fi
	
	repoDir=$WORK_DIR".git/"
	if [ ! -d $repoDir ]; then
		echo "仓库路径: $repoDir 不存在，不是Git仓库！"
		help
		exit -1
	fi
}


# 查看仓库大小
function getRepoSize() {
	size=`du $WORK_DIR -h -d 1 | grep "./.git" | awk '{ print $1 }' `
	echo $size
}

PACK_IDX_ARR=""
# 获取仓库中的pack索引项
function getPackIdxFileList() {
	packDir=$WORK_DIR".git/objects/pack/"
	PACK_IDX_ARR=`ls $packDir | grep ".idx" `
}


# 判断文件名是否可以清理
function isDeletable() {
	fileName=$1
	# 文件名最后一个字符
	finalChar=${fileName: -1}
	# 判断文件名最后一个字符
	for type in ${DELETABLE_SUFFIXW[@]}
	do
		if [ $finalChar = $type ]; then
			echo "文件【$fileName】 可以从提交日志中清除，因为它的最后一个字符是【$type】"
			return 1
		fi
	done
	# 文件名文件类型，获取文件名可以用 fileName=${fileName%.*}
	fileType=${fileName##*.}
	# 判断文件名后缀
	for type in ${DELETABLE_SUFFIXS[@]}
	do		
		if [ $fileType == $type ]; then
			echo "文件【$fileName】 可以从提交日志中清除，因为它的文件类型是【$type】"
			return 1
		fi
	done
	return 0
}

#isDeletable "上证指数.exe"
#echo "是否可以被删除"$?

# 可以删除的文件名列表
declare -A DELETABLE_FILES
# 计算可以可以清除的文件
function computeFilesCanBeDeleted() {
	fileSha1Keys=$1
	files=`git rev-list --objects --all | grep -E "$fileSha1Keys" | awk -F" *" ' !distinctx[$2]++ { print $2 }' `
	
	for file in ${files[@]}
	do
		isDeletable $file
		deletable=$?
		if [ $deletable = 1 ]; then
			DELETABLE_FILES[$file]=1
		fi
	done
}

# 执行仓库清理
function doCleanRepo() {
	if [ $TEST"" != "clean" ]; then
		echo "如果要执行清除，请输入清除命令 <clean>"
		return
	fi
	total=${#DELETABLE_FILES[@]}
	echo "可清理的文件数量：$total"
	echo "=================================================================="
	count=0
	for clean in ${!DELETABLE_FILES[@]}
	do
		# 文件可以清除，执行清除命令
		let count++
		echo ">>>>>>>>>> 执行清除命令($count/$total): $clean"
		git filter-branch -f --index-filter "git rm -f --cached --ignore-unmatch $clean" -- --all 2>&1 >> $CURR_DIR/repo_clean_history.log
		echo ">>>>>>>>>> 已清除($count/$total): $clean"
	done
	echo "=================================================================="
	
	rm -Rf .git/refs/original &> /dev/null
	rm -Rf .git/logs &> /dev/null
	git gc &> /dev/null
	
	# 计算清理后仓库大小并打印
	echo "清理后仓库大小: $(getRepoSize)"
}

# 获取每个pack idx中记录的文件大小满足扫描的sha1值
function cleanLargeFileInCommitsFromPackIdx() {
	packIdxPath=$WORK_DIR".git/objects/pack/"$1
	sha1Lines=$(git verify-pack -v $packIdxPath | sort -k 3 -n -r | head -n 200 | awk -F" *" ' $3 > "'$DELTEABLE_FILE_MIN'" ' | awk -F" *" '{ print $1 }' ) 
	for sha in ${sha1Lines[@]}
	do 
		LARGE_SHAS+="$sha|"
	done

	LARGE_SHAS=${LARGE_SHAS%|}
}

LARGE_SHAS=""
function preCleanFromPackIdxs() {
	for packIdx in ${PACK_IDX_ARR[@]}
	do 
		cleanLargeFileInCommitsFromPackIdx $packIdx
		LARGE_SHAS+="|"
	done
	LARGE_SHAS=${LARGE_SHAS%|}
	
	computeFilesCanBeDeleted $LARGE_SHAS
	echo "可以清除的文件有: ${!DELETABLE_FILES[@]}"
}

function help() {
	echo ""
	echo ""
	echo "用法: ./clean_git_repo.sh <仓库路径> [clean]"
	echo "如果需要执行清除则加上'clean',否则不加'clean',则仅打印出哪些文件可以被清理。"
	echo ""
	echo ""
}


# >>>>>>>>>> 执行流程 <<<<<<<<<<<<<<<
echo "开始时间: $(date)"
# 判断是否为Git仓库
isGitDir
echo "待清理的仓库路径为: $WORK_DIR"

# 切换到仓库所在的路径
cd $WORK_DIR

# 获取清理前仓库大小
echo "清理前仓库大小: $(getRepoSize)"

# 获取清理仓库记录的 pack idx文件
getPackIdxFileList

# 逐个从pack idx文件中查找可以清除的文件
preCleanFromPackIdxs

# 执行仓库清理
doCleanRepo

echo "结束时间：$(date)"
# 切回当前路径
cd $PWD
# >>>>>>>>>> 执行流程 <<<<<<<<<<<<<<<
