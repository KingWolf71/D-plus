1. priority is on VM execution speed
2. don't use command line compiler as it won't work; I can compile manually via IDE
3. always leave definitions at beginning of procedure - no exceptions
4. No procedure static variables; we use global variables which can be reset between runs
5. if there is an _*.ver file add a .1 everytime we interact (MAJ.MIN.FIX)
6. don't touch the *.lj files unless I expressively ask you to
7. Purebasic functions and variables and constants are case insesitive
8. Compiler flow pre-processor - scanner - AST - codegenerator - postprocessor
9. Postprocessor is crucial to properly correct JMP and CALL calls
10. Postprocessor is crucial and final step to make sure type "guessing" is not needed in the VirtualMachine
11. don't try to compile yourself
12. use powershell commands
13. gVarMeta CANNOT be used in VM code as VM needs to work independently of compiler
14. var1 + var2 is the same as var1 = var1 + var2 and va1 - var2 is the same as var1 = var1 - var2
15. LJ Language is meant to be built for speed of execution
16. Don't use intermidiate variables in VM code if possible for even faster execution
17. create a 7z backup with version under backups\ at least 2 times a day and before any major version

