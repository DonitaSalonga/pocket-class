# Pocket Class

A school-project iPhone app where teachers share presentation and exercise files with the students in their courses.

## People

**Teacher**:
A user who creates courses and uploads files to them. The role is chosen at sign-up and never changes.
_Avoid_: Instructor, admin, owner

**Student**:
A user who joins courses and opens their files. The role is chosen at sign-up and never changes.
_Avoid_: Learner, member

## Courses

**Course**:
A class owned by exactly one teacher that holds presentations and exercises.
_Avoid_: Class, classroom, subject

**Join Code**:
A short code a teacher shares so students can join a course.
_Avoid_: Invite code, course code

**Roster**:
The students currently in a course. Only the course's teacher can see it.
_Avoid_: Class list, members, enrollment

## Files

**Presentation**:
A slide file a teacher uploads to a course (`.pptx`, `.ppt`, `.key`, `.pdf`).
_Avoid_: PPT, slides, deck, lesson

**Exercise**:
A practice file a teacher uploads to a course for students to open (`.pdf`, `.docx`, `.pptx`). Students do not submit answers in the app.
_Avoid_: Assignment, homework, activity, quiz
