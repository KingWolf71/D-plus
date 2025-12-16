1. priority is on VM execution speed
2. Linux compilation: wsl -d Ubuntu-24.04 -e bash -c "export PUREBASIC_HOME=/home/terence/Apps/purebasic621 && cd /mnt/d/OneDrive/WIP/Sources/Intense.2020/lj2 && \$PUREBASIC_HOME/compilers/pbcompiler c2-modules-V20.pb -e lj2_linux -t -cl 2>&1" (use -t for thread-safe, -cl for console mode)
3. always leave definitions at beginning of procedure - no exceptions
4. No procedure static variables; we use global variables which can be reset between runs
5. if there is an _*.ver file add a .1 everytime we interact (MAJ.MIN.FIX)
6. don't touch the *.lj files unless I expressively ask you to
7. Purebasic functions and variables and constants are case insesitive
8. Compiler flow pre-processor - scanner - AST - codegenerator - postprocessor
9. Postprocessor is crucial to properly correct JMP and CALL calls
10. Postprocessor is crucial and final step to make sure type "guessing" is not needed in the VirtualMachine
11. backup should always be the first step while changing version be the last
12. use powershell commands
13. gVarMeta CANNOT be used in VM code as VM needs to work independently of compiler
14. var1 + var2 is the same as var1 = var1 + var2 and va1 - var2 is the same as var1 = var1 - var2
15. LJ Language is meant to be built for speed of execution
16. Don't use intermidiate variables in VM code; use macros instead for readility
17. create a 7z backup with version under backups\ at least 2 times a day and before any major version
18. No structure unions; we need to maintain compatibility with Spiderbasic
19. Linux GUI runs non-threaded (GTK threading causes GUI unresponsiveness); Windows GUI uses threading with queue-based updates
