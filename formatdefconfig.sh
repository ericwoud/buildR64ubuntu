#!/bin/bash

DEFCONFIG="./defconfig"
WORK="./formatdef"
[ -z $ARCH ] && ARCH="arm64"

echo "ARCH="$ARCH

mkdir -p $WORK

cp -f $DEFCONFIG $WORK/defconfig_unformatted

######################################
# Make allyes.config with extras     #
# Add more allyes extras below 'cat' #
######################################
filename=$WORK/allyes.config
cat >$WORK/allyesextra <<'EOF'
CONFIG_CMDLINE="yes"
CONFIG_CMDLINE_FORCE=y
# CONFIG_LOCALVERSION_AUTO is not set
CONFIG_COMPILE_TEST=n
CONFIG_PREEMPT=y
CONFIG_CPU_BIG_ENDIAN=n
EOF
make KCONFIG_ALLCONFIG=$WORK/allyesextra ARCH=$ARCH allyesconfig
cp ./.config $filename

###############################################################################
# Format the defconfig, uses allyes.config, if not perfect, needs extras #
###############################################################################
countconfig=0
echo -e "#\n# defconfig file build by:\n#   https://github.com/ericwoud/formatdefconfig.git" >$WORK/defconfig
while read line; do
    if [[ ! -z "$line" ]]; then
      string=""
      if [[ ${line:0:7} == 'CONFIG_' ]]; then
        string="${line%%=*}"
      elif [[ ${line:0:9} == '# CONFIG_' ]]; then
        string=${line%' is not set'}
        string=${string:2}
      fi
      if [[ ! -z "$string" ]]; then
        lineout=$(grep "$string[ =]" $WORK/defconfig_unformatted)
        if [ -n "$lineout" ]; then
          echo -e "$lineout" >>$WORK/defconfig
          countconfig=$((countconfig+1))
          echo Formatting line nr: $countconfig
          tput cuu1 # scroll up
        fi
      else
        echo -e "$line" >>$WORK/defconfig
      fi
    else
      echo -e "" >>$WORK/defconfig
    fi
done < $filename

#######################################################################
# Clean up the defconfig, leave out the comments with no options #
#######################################################################
while [[ $changed != "false" ]]; do
  changed="false"
  readarray -t fileout < $WORK/defconfig
  for (( i=3; i<${#fileout[@]}; i++ ))
  do  
    if [[ ${fileout[i-3]} == '#' ]]; then
      if [[ ${fileout[i-2]:0:2} == '# ' ]]; then
        if [[ ${fileout[i-1]} == '#' ]]; then
          endof='# end of'${fileout[i-2]/'#'}
          if [[ ${fileout[i]} == "$endof" ]]; then
            fileout[i-3]="&"
            fileout[i-2]="&"
            fileout[i-1]="&"
            fileout[i]="&"
            changed="true"
          elif [[ ${fileout[i]:0:7} != 'CONFIG_' ]]  && [[ ${fileout[i]:0:9} != '# CONFIG_' ]]; then
            test="$(grep -F "$endof" $WORK/defconfig)"
            if [ -z "$test" ] || [[ ${fileout[i-2]} == '# Boot options' ]]; then
              fileout[i-3]="&"
              fileout[i-2]="&"
              fileout[i-1]="&"
              changed="true"
            fi
          fi
        fi
      fi
    fi
    if [[ ${fileout[i-1]} == '' ]]; then
      if [[ ${fileout[i]} == '' ]]; then
        fileout[i-1]="&"
        changed="true"
      elif [[ ${fileout[i]:0:9} == '# end of ' ]]; then
        fileout[i-1]="&"
        changed="true"
      elif [[ ${fileout[i-2]:0:7} == 'CONFIG_' ]]  || [[ ${fileout[i-2]:0:9} == '# CONFIG_' ]]; then
        if [[ ${fileout[i]:0:7} == 'CONFIG_' ]]  || [[ ${fileout[i]:0:9} == '# CONFIG_' ]]; then
          fileout[i-1]="&"
          changed="true"
        fi
      fi
    fi
  done  
  echo -e -n "" >$WORK/defconfig
  for lineout in "${fileout[@]}"; do
    if [[ "$lineout" != "&" ]]; then
     echo -e "$lineout" >>$WORK/defconfig
    fi
  done
done

echo PRINTING DIFFERENCES check formatting, SHOULD BE NONE
./scripts/diffconfig $WORK/defconfig_unformatted $WORK/defconfig
echo PRINTING DIFFERENCES check formatting, DONE
echo If there are differences after formatting found, you need to add the CONFIG_* 
echo to the allyes extras inside the script with any value. The value is not used.

##########################################
# Check if defconfig actually works #
##########################################
cp $WORK/defconfig_unformatted ./arch/$ARCH/configs/test1_defconfig
cp $WORK/defconfig             ./arch/$ARCH/configs/test2_defconfig
make ARCH=$ARCH test1_defconfig
cp ./.config $WORK/test1.config
make ARCH=$ARCH test2_defconfig
cp ./.config $WORK/test2.config
echo PRINTING DIFFERENCES defconfig, SHOULD BE NONE
./scripts/diffconfig $WORK/test1.config $WORK/test2.config
echo PRINTING DIFFERENCES defconfig, DONE
rm -f ./arch/$ARCH/configs/test?_defconfig

echo -e "\nALL DONE. IF NO DIFFERENCES PRINTED YOU CAN USE $WORK/defconfig"

exit 0

