## gentoo.sh ##

install gentoo/linux quickly

    gentoo.sh \
        --arch amd64|x86|arm \
        --keywords amd64|x86|arm \
        --platform generic|mbp|pi \
        --mirrors http://mirrors.163.com/gentoo/ http://mirrors.sohu.com/gentoo/ \
        --rsync rsync.cn.gentoo.org \
        --stage3 /path/to/stage3 \
        --portage /path/to/portage \
        --firmware /path/to/firmware \
        --hostname gentoo \
        --timezone Asia/Shanghai \
        --public-key /path/to/public.key \
        --luks /path/to/dmcrypt.key
