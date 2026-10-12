# Independent verification: spec 001

Commands were run in the requested order. Exit status: 0 for each command.

## Exact outcomes

- `just lint`: PASS; LuaLS completed across 86 files with no problems.
- `just format`: PASS; Stylua formatting completed.
- `just format-check`: PASS; Stylua check completed.
- `just test`: PASS; unit 50/50, integration 183/183, functional 60/60; total 293 passed, 0 failed.

## Full command output

### just lint

```text
Initializing ...
                                                                                
>=================== 01/86
                                                                                
>>>================= 09/86
                                                                                
>>>>>>============== 22/86
                                                                                
>>>>>>>>>=========== 38/86
                                                                                
>>>>>>>>>>>>======== 48/86
                                                                                
>>>>>>>>>>>>>======= 54/86
                                                                                
>>>>>>>>>>>>>>>===== 64/86
                                                                                
>>>>>>>>>>>>>>>>>=== 73/86
                                                                                
>>>>>>>>>>>>>>>>>>== 74/86
                                                                                
>>>>>>>>>>>>>>>>>>>= 79/86
                                                                                
>>>>>>>>>>>>>>>>>>>> 86/86
                                                                                
Diagnosis completed, no problems found
```

### just format

```text
stylua lua plugin sandbox scripts tests
```

### just format-check

```text
stylua --check lua plugin sandbox scripts tests
```

### just test

```text
unit: executed 50, passed 50, failed 0
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
.../Desktop/home-repos/diffreview/lua/diffreview/review.lua:279: Review identity changed; start a new review
stack traceback:
	[C]: in function 'error'
	.../Desktop/home-repos/diffreview/lua/diffreview/review.lua:279: in function <.../Desktop/home-repos/diffreview/lua/diffreview/review.lua:262>
	[C]: in function 'xpcall'
	.../Desktop/home-repos/diffreview/lua/diffreview/review.lua:262: in function <.../Desktop/home-repos/diffreview/lua/diffreview/review.lua:261>
Review stopped
Review stopped
.../Desktop/home-repos/diffreview/lua/diffreview/review.lua:303: EISDIR: illegal operation on a directory: /home/bymse/Desktop/home-repos/diffreview/.artifacts/diff-review-tests.AB01ps/tmp/nvim.bymse/gmLMF3/109/.git/diffreview-nvim/1f718ba6fbc9d72056b93626a4dcd831a6c3e9dcfc6f5e89e9b973df4f44089f.json.7449871890905.tmp -> /home/bymse/Desktop/home-repos/diffreview/.artifacts/diff-review-tests.AB01ps/tmp/nvim.bymse/gmLMF3/109/.git/diffreview-nvim/1f718ba6fbc9d72056b93626a4dcd831a6c3e9dcfc6f5e89e9b973df4f44089f.json
stack traceback:
	[C]: in function 'error'
	.../Desktop/home-repos/diffreview/lua/diffreview/review.lua:303: in function <.../Desktop/home-repos/diffreview/lua/diffreview/review.lua:262>
	[C]: in function 'xpcall'
	.../Desktop/home-repos/diffreview/lua/diffreview/review.lua:262: in function <.../Desktop/home-repos/diffreview/lua/diffreview/review.lua:261>
.../Desktop/home-repos/diffreview/lua/diffreview/review.lua:279: Review identity changed; start a new review
stack traceback:
	[C]: in function 'error'
	.../Desktop/home-repos/diffreview/lua/diffreview/review.lua:279: in function <.../Desktop/home-repos/diffreview/lua/diffreview/review.lua:262>
	[C]: in function 'xpcall'
	.../Desktop/home-repos/diffreview/lua/diffreview/review.lua:262: in function <.../Desktop/home-repos/diffreview/lua/diffreview/review.lua:261>
Review stopped
.../Desktop/home-repos/diffreview/lua/diffreview/review.lua:295: Unable to load matching selected review content
stack traceback:
	[C]: in function 'error'
	.../Desktop/home-repos/diffreview/lua/diffreview/review.lua:295: in function <.../Desktop/home-repos/diffreview/lua/diffreview/review.lua:262>
	[C]: in function 'xpcall'
	.../Desktop/home-repos/diffreview/lua/diffreview/review.lua:262: in function 'perform'
	.../Desktop/home-repos/diffreview/lua/diffreview/review.lua:334: in function 'refresh'
	...os/diffreview/tests/integration/review_refresh_tests.lua:277: in function 'run'
	...Desktop/home-repos/diffreview/tests/helpers/git_repo.lua:106: in function <...Desktop/home-repos/diffreview/tests/helpers/git_repo.lua:105>
	[C]: in function 'xpcall'
	...Desktop/home-repos/diffreview/tests/helpers/git_repo.lua:105: in function 'with_repo'
	...os/diffreview/tests/integration/review_refresh_tests.lua:251: in function 'selected_failure_case'
	...os/diffreview/tests/integration/review_refresh_tests.lua:296: in function <...os/diffreview/tests/integration/review_refresh_tests.lua:295>
	[C]: in function 'xpcall'
	tests/run.lua:119: in function <tests/run.lua:118>
Review stopped
.../Desktop/home-repos/diffreview/lua/diffreview/review.lua:295: Unable to load matching selected review content
stack traceback:
	[C]: in function 'error'
	.../Desktop/home-repos/diffreview/lua/diffreview/review.lua:295: in function <.../Desktop/home-repos/diffreview/lua/diffreview/review.lua:262>
	[C]: in function 'xpcall'
	.../Desktop/home-repos/diffreview/lua/diffreview/review.lua:262: in function 'perform'
	.../Desktop/home-repos/diffreview/lua/diffreview/review.lua:334: in function 'refresh'
	...os/diffreview/tests/integration/review_refresh_tests.lua:277: in function 'run'
	...Desktop/home-repos/diffreview/tests/helpers/git_repo.lua:106: in function <...Desktop/home-repos/diffreview/tests/helpers/git_repo.lua:105>
	[C]: in function 'xpcall'
	...Desktop/home-repos/diffreview/tests/helpers/git_repo.lua:105: in function 'with_repo'
	...os/diffreview/tests/integration/review_refresh_tests.lua:251: in function 'selected_failure_case'
	...os/diffreview/tests/integration/review_refresh_tests.lua:290: in function <...os/diffreview/tests/integration/review_refresh_tests.lua:289>
	[C]: in function 'xpcall'
	tests/run.lua:119: in function <tests/run.lua:118>
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
No changes to review
Review stopped
Unable to inspect repository files
Review stopped
Review stopped
No review is active
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Invalid review state schema
Invalid review state schema
Invalid review state schema
Invalid review file record
Review stopped
EACCES: permission denied: /home/bymse/Desktop/home-repos/diffreview/.artifacts/diff-review-tests.AB01ps/tmp/nvim.bymse/gmLMF3/132/.git/diffreview-nvim/fab803428adc993b738faf1e20ed8d55d091a11754565c28c7eec6a2421e3380.json
Review stopped
A review is already starting or active
Review stopped
No review is active
Review stopped
Review state is not a file
Review stopped
Review stopped
Review stopped
No changes to review
Review stopped
Review stopped
Review stopped
Review start canceled
Review stopped
No review is active
Review stopped
No review is active
integration: executed 183, passed 183, failed 0
Review stopped
Review stopped
Review stopped
Review stopped
No review is active
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Invalid review start options
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
No review is active
Review stopped
No review is active
Review stopped
No review is active
Review stopped
No review is active
Review stopped
No review is active
Review stopped
No review is active
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
No review is active
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
Review stopped
functional: executed 60, passed 60, failed 0
```
