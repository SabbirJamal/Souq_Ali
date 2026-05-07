# souqali

A new Flutter project.

## Getting Started

so the app uses firebase clean up method to automatically delete data from the database and storage.
now in cloud, i have set firebase to give a check on database every 24hrs and delete data.
this data deletion algorithm is - the seller uploads at 1pm with time period 3hrs, the app automatically 
calculates how much time is 3hrs from time uploaded and sets the into expires_at column = 4pm.
after 24hrs google console does a cleanup check, and when it finds out that expires time is less than current time
it delete the record along with images everything.

if you want to change cleanup from 24 hrs to some other time then head to functions/index.js
there will be a query schedule: "every 24 hours", change 24 to any value desired. And after doing it,
open powershell, head to root folder, and run this command 'firebase.cmd deploy --only functions:cleanupExpiredItems'
