/* Root-only Android FUSE helper, restricted to one app-private mountpoint. */
#define _GNU_SOURCE
#include <sys/mount.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/xattr.h>
#include <limits.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int main(int argc,char **argv){
 if(geteuid()!=0){fprintf(stderr,"Root is required\n");return 1;}
 if(argc<2)return 1;
 char target[PATH_MAX]; if(!realpath(argv[argc-1],target)){perror("mountpoint");return 1;}
 if(strcmp(target,"/data/user/0/com.tencent.ig/files/network-games") && strcmp(target,"/data/data/com.tencent.ig/files/network-games")){fprintf(stderr,"Unexpected mountpoint: %s\n",target);return 1;}
 int unmounting=0,lazy=0;unsigned long flags=MS_NOSUID|MS_NODEV;
 for(int i=1;i<argc-1;i++){
  if(!strcmp(argv[i],"-u"))unmounting=1;
  else if(!strcmp(argv[i],"-z"))lazy=1;
  else if(!strcmp(argv[i],"-o")&&i+1<argc-1){
   char *options=strdup(argv[++i]),*save=NULL;if(!options)return 1;
   for(char *v=strtok_r(options,",",&save);v;v=strtok_r(NULL,",",&save)){
    if(!strcmp(v,"ro"))flags|=MS_RDONLY;
    else if(!strcmp(v,"noexec"))flags|=MS_NOEXEC;
   }free(options);
  }
 }
 if(unmounting){if(umount2(target,lazy?MNT_DETACH:0)){perror("FUSE unmount");return 1;}return 0;}
 const char *env=getenv("_FUSE_COMMFD");char *end=NULL;
 if(!env||!*env){fprintf(stderr,"Missing FUSE socket\n");return 1;}
 long comm=strtol(env,&end,10);if(*end||comm<0||comm>INT_MAX)return 1;
 char context[1024]={0};ssize_t n=getxattr(target,"security.selinux",context,sizeof(context)-1);
 if(n<=0||strncmp(context,"u:object_r:app_data_file:s0",25)||strchr(context,'"')){fprintf(stderr,"Unexpected mountpoint SELinux label\n");return 1;}
 int fd=open("/dev/fuse",O_RDWR|O_CLOEXEC);if(fd<0){perror("/dev/fuse");return 1;}
 char data[2048];snprintf(data,sizeof(data),"fd=%d,rootmode=40000,user_id=0,group_id=0,allow_other,max_read=1048576",fd);
 if(mount("tyrantlator-network",target,"fuse.rclone",flags,data)){perror("FUSE mount");close(fd);return 1;}
 char byte=0,control[CMSG_SPACE(sizeof(int))];memset(control,0,sizeof(control));
 struct iovec io={.iov_base=&byte,.iov_len=1};struct msghdr msg={0};msg.msg_iov=&io;msg.msg_iovlen=1;msg.msg_control=control;msg.msg_controllen=sizeof(control);
 struct cmsghdr *c=CMSG_FIRSTHDR(&msg);c->cmsg_level=SOL_SOCKET;c->cmsg_type=SCM_RIGHTS;c->cmsg_len=CMSG_LEN(sizeof(int));memcpy(CMSG_DATA(c),&fd,sizeof(fd));
 if(sendmsg((int)comm,&msg,0)<0){perror("FUSE descriptor send");umount(target);close(fd);return 1;}
 close(fd);return 0;
}
