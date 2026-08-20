import app from './app.js';

const PORT = process.env.PORT || 4000;

app.listen(PORT, () => {
    console.log(`Microservicio de autorización ejecutándose en el puerto ${PORT}`);
});
