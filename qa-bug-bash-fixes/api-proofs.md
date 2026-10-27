## API proofs (local build, admin session, 27 Oct 2026)
H1  POST /users/bulk/invite {emails:[2 active members]} -> 409 {"code":"HTTP_CONFLICT","message":"All provided emails already have active accounts"}
M1  POST /users/bulk/invite {emails:['"rishabh@pipeshub.app")']} -> 400 {"message":"Invalid emails are found"}
M8a POST /conversations/attachments/upload qa-octet.csv as application/octet-stream -> 200 mimeType "text/csv"
M8b POST /conversations/attachments/upload qa.zip as application/zip -> 400 "Unsupported attachment type: qa.zip (received content type: application/zip). Supported types: ..."
L14c POST /users/bulk/invite/upload groupIds=not-json -> 400 "groupIds must be a JSON array of group ids, such as [\"<id>\"]"
L14d POST /users/bulk/invite/upload 6 MB file -> 400 "This file is larger than the 5 MB limit. Make it smaller or split it, then upload it again."
M5  two parallel POST /knowledgebase/:kb/upload of qa-race.csv -> #1 file:failed DUPLICATE_NAME ("A file named \"qa-race.csv\" already exists in this location; it was skipped."), #2 file:succeeded; records named qa-race afterwards: 1
L4  PUT /knowledgeBase/:kb/folder/:id {"folderName":"a/b"} -> 400 VALIDATION_ERROR "Folder names cannot contain \"/\" or \"\\\"."
L16 Download as CSV on an answer table -> saved as ~/Downloads/row-20261027-195131.csv (header "Row,Industry", 3 rows), previously always table.csv
L10 Copy image -> clipboard PNG 548x2000 px (was 380x1388 on demo), toast "Diagram image copied"
H4  Stop clicked during section 2 -> GET /conversations/:id: bot_response status="stopped", content 3081 chars ending "...Leonardo da Vinci, who lived from 1452 to"; conversation.status="Stopped" (demo before fix: content 0 chars). Partial answer + Stopped marker still shown after reload.
M2  [member] PUT /users/<own id> {"hasLoggedIn":false} -> 403 "Only admins can change whether a user has signed in"
L13 [member] PUT /users/<other user> {"designation":"x"} -> 403 "You don't have admin access and can't change other users" (was 400 "You dont have...")
M9  [member, not in team] GET /teams/:id -> 404 "This team was removed, or you no longer have access..." (was 200 with team details)
M9  [member, not in team] GET /teams/:id/users -> 404
L13 [member, not in team] PUT /teams/:id -> 404 and DELETE -> 404 (PUT was 403 before, now matches DELETE)
L13 [member, READER of team] PUT /teams/:id -> 403 "User does not have permission to update this team"; DELETE -> 403
H2  [member app] POST /teams "QA Member Team Local" -> 201; [admin, not in team] list includes it with canEdit/canManageMembers/canDelete = true; PUT rename -> 200 ("QA Member Team (admin edit)"); row menu Delete -> "Team deleted"
H2  [admin] All team canDelete=false; DELETE /teams/all_<org> -> 403 "The default All team cannot be deleted"
H2  [member 998] GET /teams/user/teams -> only teams 998 belongs to (QA Member Team Local, QA-Team-C, Personal_team, All); admin-only teams such as "QA Toast Check" not listed
