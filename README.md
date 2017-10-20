## gentoo.sh ##

install gentoo/linux quickly

    gentoo.sh \
		--dev=/dev/vda \
        --platform=generic|mbp|pi \
        --mirrors="http://mirrors.163.com/gentoo/ http://mirrors.sohu.com/gentoo/" \
        --rsync=rsync.cn.gentoo.org \
        --stage3=/path/to/stage3 \
        --portage=/path/to/portage \
        --firmware=/path/to/firmware \
		--config=/path/to/kernel/config \
        --hostname=gentoo \
        --timezone=Asia/Shanghai \
        --public-key=/path/to/public.key \
        --luks=/path/to/dmcrypt.key \
		--mode=install
