const express = require('express');
const { MongoClient, ObjectId } = require('mongodb');
const path = require('path');

// --- НАЛАШТУВАННЯ БАЗИ ДАНИХ ТА КЕШУВАННЯ ---
const URL = 'mongodb://localhost:27017';
const DB_NAME = 'blog_system';
const client = new MongoClient(URL);
let db;

// Система кешування в пам'яті (in-memory cache) (Рівень 3)
const cache = {};
const CACHE_TTL = 30000; // Час життя кешу: 30 секунд

async function connectDB() {
    try {
        await client.connect();
        db = client.db(DB_NAME);
        console.log(`✅ Підключено до MongoDB: ${DB_NAME}`);
    } catch (error) {
        console.error('❌ Помилка підключення до MongoDB:', error);
        process.exit(1);
    }
}

const app = express();
const PORT = 3000;

app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// --- API ENDPOINTS ---

// 1. GET /api/posts: Список постів з пагінацією та пошуком
// ... (Залишити без змін, як у Частині 3) ...

app.get('/api/posts', async (req, res) => {
    try {
        const page = parseInt(req.query.page) || 1;
        const limit = parseInt(req.query.limit) || 10;
        const skip = (page - 1) * limit;
        const search = req.query.search;
        
        let matchQuery = { status: "published" };

        if (search) {
            matchQuery = {
                ...matchQuery,
                $text: { $search: search }
            };
        }
        
        // --- Логіка Кешування (Рівень 3) ---
        const cacheKey = `posts_p${page}_l${limit}_s${search || ''}`;
        if (cache[cacheKey] && (Date.now() - cache[cacheKey].timestamp < CACHE_TTL)) {
            console.log(`[Cache Hit] Serving posts from cache: ${cacheKey}`);
            return res.json(cache[cacheKey].data);
        }
        // -------------------------------------

        const pipeline = [
            { $match: matchQuery },
            { $sort: { published_at: -1 } },
            { $skip: skip },
            { $limit: limit },
            {
                $project: {
                    _id: 1,
                    title: 1,
                    slug: 1,
                    excerpt: 1,
                    tags: 1,
                    featured_image: 1,
                    created_at: 1,
                    author: { username: 1 },
                    category: { name: 1 },
                    statistics: { views: 1, likes: 1 }
                }
            }
        ];

        const posts = await db.collection('posts').aggregate(pipeline).toArray();
        const totalCount = await db.collection('posts').countDocuments(matchQuery);

        const responseData = {
            posts,
            currentPage: page,
            totalPages: Math.ceil(totalCount / limit),
            totalPosts: totalCount
        };

        // Кешування результату
        cache[cacheKey] = { data: responseData, timestamp: Date.now() };
        console.log(`[Cache Miss] Data cached: ${cacheKey}`);

        res.json(responseData);

    } catch (error) {
        res.status(500).json({ error: 'Помилка при отриманні постів: ' + error.message });
    }
});


// 2. GET /api/posts/:slug: Детальний пост (Залишити без змін, інкрементація переглядів працює тут)
app.get('/api/posts/:slug', async (req, res) => {
    try {
        const post = await db.collection('posts').findOne({ slug: req.params.slug });

        if (!post) {
            return res.status(404).json({ error: 'Пост не знайдено.' });
        }

        await db.collection('posts').updateOne(
            { _id: post._id },
            { $inc: { "statistics.views": 1 } }
        );

        res.json(post);
    } catch (error) {
        res.status(500).json({ error: 'Помилка при отриманні детального посту.' });
    }
});


// 3. POST /api/posts/:id/comment: Додавання вкладеного коментаря та сповіщення (Рівень 3)
app.post('/api/posts/:id/comment', async (req, res) => {
    try {
        const postId = new ObjectId(req.params.id);
        const { author_id, username, text, parent_id } = req.body;

        if (!text || !author_id) {
            return res.status(400).json({ error: 'Текст коментаря та ID автора обов\'язкові.' });
        }
        
        const newComment = {
            comment_id: new ObjectId(),
            author: {
                user_id: new ObjectId(author_id),
                username: username || 'Anonymous'
            },
            text,
            created_at: new Date(),
            status: 'pending',
            likes: 0,
            // parent_id дозволяє вкладеність коментарів (Рівень 3)
            parent_id: parent_id ? new ObjectId(parent_id) : null 
        };

        const result = await db.collection('posts').updateOne(
            { _id: postId },
            { 
                $push: { comments: newComment },
                $inc: { "statistics.comments_count": 1 }
            }
        );
        
        if (result.matchedCount === 0) {
            return res.status(404).json({ error: 'Пост не знайдено.' });
        }

        // --- Система Сповіщень (Рівень 3) ---
        const post = await db.collection('posts').findOne({ _id: postId }, { projection: { title: 1, 'author.user_id': 1 } });
        
        await db.collection('notifications').insertOne({
            user_id: post.author.user_id, // Сповіщаємо автора посту
            type: "new_comment",
            message: `Новий коментар від ${newComment.author.username} до вашої статті: "${post.title.substring(0, 30)}..."`,
            read: false,
            created_at: new Date()
        });
        // ----------------------------------------

        res.status(201).json({ message: 'Коментар додано, очікує модерації.' });

    } catch (error) {
        res.status(500).json({ error: 'Помилка при додаванні коментаря: ' + error.message });
    }
});


// 4. POST /api/posts/:id/update: Оновлення та Версіонування Посту (Рівень 3)
app.post('/api/posts/:id/update', async (req, res) => {
    try {
        const postId = new ObjectId(req.params.id);
        const { title, content, editor_id } = req.body;

        if (!editor_id) {
             return res.status(401).json({ error: 'Необхідний ID редактора.' });
        }

        // 1. Отримання поточної версії для версіонування
        const oldPost = await db.collection('posts').findOne({ _id: postId });
        if (!oldPost) {
            return res.status(404).json({ error: 'Пост не знайдено.' });
        }
        
        const currentVersion = oldPost.version || 1;
        
        // 2. Збереження старої версії в history
        await db.collection('post_history').insertOne({
            post_id: oldPost._id,
            version: currentVersion,
            editor_id: new ObjectId(editor_id),
            edited_at: oldPost.updated_at,
            content_snapshot: oldPost.content,
            title_snapshot: oldPost.title
        });

        // 3. Оновлення посту з інкрементом версії
        const updateResult = await db.collection('posts').updateOne(
            { _id: postId },
            { 
                $set: { 
                    title: title || oldPost.title, 
                    content: content || oldPost.content,
                    updated_at: new Date() 
                },
                $inc: { version: 1 } // Інкрементуємо номер версії
            }
        );
        
        // Очищаємо кеш, оскільки дані оновилися
        Object.keys(cache).forEach(key => delete cache[key]);
        
        res.json({ 
            message: `Пост оновлено. Створена версія: ${currentVersion}`,
            newVersion: currentVersion + 1
        });

    } catch (error) {
        res.status(500).json({ error: 'Помилка при оновленні та версіонуванні: ' + error.message });
    }
});


// 5. GET /api/stats/top-authors: Аналітичний запит з Кешуванням (Рівень 3)
app.get('/api/stats/top-authors', async (req, res) => {
    const cacheKey = 'topAuthors';
    
    // --- Логіка Кешування (Рівень 3) ---
    if (cache[cacheKey] && (Date.now() - cache[cacheKey].timestamp < CACHE_TTL)) {
        console.log(`[Cache Hit] Serving top authors from cache.`);
        return res.json(cache[cacheKey].data);
    }
    // -------------------------------------
    
    try {
        const result = await db.collection('posts').aggregate([
            { $match: { status: "published" } },
            {
                $group: {
                    _id: "$author.user_id",
                    username: { $first: "$author.username" },
                    posts_count: { $sum: 1 },
                    total_views: { $sum: "$statistics.views" }
                }
            },
            { $sort: { posts_count: -1 } },
            { $limit: 10 },
            { $project: { _id: 0, username: 1, posts_count: 1, total_views: 1 } }
        ]).toArray();
        
        // Кешування результату
        cache[cacheKey] = { data: result, timestamp: Date.now() };
        console.log(`[Cache Miss] Top authors data cached.`);

        res.json(result);
        
    } catch (error) {
        res.status(500).json({ error: 'Помилка при отриманні статистики.' });
    }
});


// --- ЗАПУСК СЕРВЕРА ---
connectDB().then(() => {
    app.listen(PORT, () => {
        console.log(`🚀 Сервер запущено на http://localhost:${PORT}`);
    });
});