Title: Secure Use of GPT APIs via Metadata Analysis
Date: 2023-07-07
LastUpdate: 2023-07-07
Category: Technology
Tags: technology, ai
Author: Chloe Bitshard
Progress: Draft
Confidence: 4
Summary: LLM usage has been criticized on a number of fronts; one of which is that by needing to use an external API, like OpenAI's, you are unable to use GPT-4 on secret information.  I propose that GPT-4 is capable of securely answering difficult questions about confidential data without exposing the data to OpenAI.

<p class="intro-paragraph drop-cap-de-zs">
One of the main roadblocks to GPT-4 adoption in production has been the need to ensure that secure data remains secure.  One area where LLM responses can be extremely useful is when answering questions about large sets of data.  In this article, I will discuss a method for generating reports on confidential data using LLMs without exposing the data to the LLM.</p>

## The Problem

Imagine you have a complex database, built up over many years.  There are a large number of tables, and the way they interconnect requires a bit of thought.

```sql
CREATE TABLE users (
  id INT PRIMARY KEY,
  name VARCHAR(255),
  email VARCHAR(255),
  password VARCHAR(255),
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);

CREATE TABLE posts (
  id INT PRIMARY KEY,
  user_id INT,
  title VARCHAR(255),
  body TEXT,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);

CREATE TABLE comments (
  id INT PRIMARY KEY,
  user_id INT,
  post_id INT,
  body TEXT,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);

CREATE TABLE likes (
  id INT PRIMARY KEY,
  user_id INT,
  post_id INT,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);

CREATE TABLE follows (
  id INT PRIMARY KEY,
  user_id INT,
  followed_user_id INT,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);

CREATE TABLE tags (
  id INT PRIMARY KEY,
  name VARCHAR(255),
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);

CREATE TABLE subscriptions (
  id INT PRIMARY KEY,
  user_id INT,
  tag_id INT,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);

CREATE TABLE referrals (
  id INT PRIMARY KEY,
  user_id INT,
  referred_user_id INT,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);

CREATE TABLE notifications (
  id INT PRIMARY KEY,
  user_id INT,
  message TEXT,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);

CREATE TABLE logins (
  id INT PRIMARY KEY,
  user_id INT,
  ip_address VARCHAR(255),
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);

CREATE TABLE locations (
  id INT PRIMARY KEY,
  user_id INT,
  latitude DECIMAL(9,6),
  longitude DECIMAL(9,6),
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);
```

This is a fairly simple database, but it's not immediately obvious how the tables are connected.  If you wanted to know how many users had liked a post, you would need to write a query like this:

```sql
SELECT COUNT(*) FROM likes WHERE post_id = 1;
```

If you wanted to know how many users had liked a post, and how many users had commented on a post, you would need to write a query like this:

```sql
SELECT COUNT(*) FROM likes WHERE post_id = 1;
SELECT COUNT(*) FROM comments WHERE post_id = 1;
``` 

If you wanted to know where the 10 users who have referred the most users who logged in within the past 24 hours are located, you would need to write a query like this:

```sql
SELECT locations.latitude, locations.longitude
FROM locations
INNER JOIN logins ON logins.user_id = locations.user_id
INNER JOIN referrals ON referrals.user_id = logins.user_id
INNER JOIN users ON users.id = referrals.referred_user_id
WHERE logins.created_at > NOW() - INTERVAL 1 DAY
GROUP BY locations.latitude, locations.longitude
ORDER BY COUNT(*) DESC
LIMIT 10;
```

The first few were pretty straightforward, but the last one was a bit more complicated.  Frequently, answering these kinds of questions requires a non-trivial amount of SQL knowledge.  If you're not a SQL expert, you might not be able to answer these questions at all.

## Enabling LLMs to Answer Questions About Confidential Data

LLMs are capable of answering questions about confidential data without exposing the data to OpenAI.  This is accomplished by using metadata analysis to determine the answer to the question.

You can ask:

<blockquote>

I have a database with the following structure:

```
CREATE TABLE users (
  id INT PRIMARY KEY,
  name VARCHAR(255),
  email VARCHAR(255),
  password VARCHAR(255),
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);

...

CREATE TABLE locations (
  id INT PRIMARY KEY,
  user_id INT,
  latitude DECIMAL(9,6),
  longitude DECIMAL(9,6),
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);
```

Where are the 10 users who have referred the most users who logged in within the past 24 hours are located?

Return the response in a json format with a key 'SQL' and a value of an SQL query to provide that information.
</blockquote>

To which ChatGPT returns:

<blockquote>
The SQL query to find this information will need to join several tables and aggregate the data in a certain way. Here is the JSON response:


```json
{
  "SQL": "
    WITH referred_users AS (
      SELECT r.user_id, COUNT(*) AS referred_count
      FROM referrals AS r
      JOIN logins AS l ON r.referred_user_id = l.user_id
      WHERE l.created_at > NOW() - INTERVAL '24 hours'
      GROUP BY r.user_id
    ), 
    ranked_users AS (
      SELECT *, RANK() OVER (ORDER BY referred_count DESC) AS rank
      FROM referred_users
    ),
    user_locations AS (
      SELECT 
        u.name, 
        u.email, 
        loc.latitude, 
        loc.longitude
      FROM users AS u
      JOIN locations AS loc ON u.id = loc.user_id
    )
    SELECT 
      u.name,
      u.email,
      u.latitude,
      u.longitude
    FROM ranked_users AS r
    JOIN user_locations AS u ON r.user_id = u.id
    WHERE r.rank <= 10
  "
}
```

This query does several things:

1. It creates a temporary table (`referred_users`) of users who have referred other users who have logged in within the past 24 hours, along with a count of such referrals.

2. It ranks these users by the number of such referrals (`ranked_users`).

3. It retrieves the most recent location of each user (`user_locations`).

4. Finally, it joins the location information with the ranked users and selects the top 10 referrers by the number of referred logins. 

Note: This query assumes that the latest location is stored for each user in the `locations` table. If there are multiple locations for a user, the query may need modification. If the database is based on PostgreSQL, for instance, the locations table could be filtered using the `DISTINCT ON (user_id)` clause to ensure that the most recent location is retrieved for each user. Similarly, MySQL could use a nested subquery to achieve the same. This is just an important aspect to consider based on how your database manages the data.
</blockquote>

## Extracting the response

The response is a JSON object with a key `SQL` and a value of an SQL query.  You can extract the SQL query from the JSON object and run it against your database to get the answer to your question.

As you can see in the example above, GPT-4 may return more than the JSON format we requested.  We can look for the first '{' and last '}' characters, and attempt to parse JSON with that string.  If it works, great, if not, we can re-ask GPT-4 the question again with a slightly different phrasing to see if it will answer more accurately.[ref]There are a number of methods to more accurately extract machine-readable data from GPT-4's responses.  The best methods continue to be researched and developed, and are out of scope for this article.[/ref]

Once the data is extracted, we can run it against our database to get the answer to our question.  Cool, right?

## YOU JUST LET GPT-4 ACCESS MY DATABASE?!

You didn't think we were ending this there.  Of course we're not going to let GPT-4 access your database.  That would be crazy.  We're going to let GPT-4 access a copy of your database, and we're going to make sure that it can't access the original database.  We're also going to only let it access a subset of the original database based on the permissions of the user requesting the data.

## How to Limit Database Access

There are a couple of mechanisms for limiting database access.  There are a variety of ways to do this that are substantially more efficient, but we're going to focus on the simplest way to do it: Building a completely new sqlite database with a subset of the data.

### Building a New Database

The first step is to build a new sqlite database with a subset of the data.  This is accomplished by running a series of SQL queries against the original database, and inserting the results into the new database.

Other options do exist, but I am not an expert in various SQL databases, and so I don't want to over-promise on the security of those options.  If you are an expert in SQL databases, you can probably come up with a better way to do this.

So for now, lets walk through the steps to build a new sqlite database with a subset of the data.

1. Create a new, temporary sqlite database, just for this purpose.
2. Create a new table in the temporary database for each table in the original database.
3. For each table in the original database, run a query to select the data you want to include in the new database, and insert it into the new table.

You can begin this process as soon as you know that you will be asking GPT-4 a question about your database.  You can even do it in the background, so that the database is ready when you need it.  For some larger databases, I am currently regenerating the database every 24 hours, overnight, so that it is ready for the next day.

Updates to the original database will not be reflected in the new database, so you may want may want to mention in your response that the data is only accurate as of a certain timestamp.